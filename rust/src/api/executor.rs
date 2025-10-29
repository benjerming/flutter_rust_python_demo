#[allow(unused_imports)]
use super::env_ext::EnvExt;
#[allow(unused_imports)]
use log::{error, info};
use std::collections::HashMap;
#[allow(unused_imports)]
use std::sync::{Mutex, OnceLock};

#[cfg(target_os = "android")]
#[flutter_rust_bridge::frb(sync)]
pub fn get_executable_interpreter(path: &str) -> Option<String> {
    use goblin::elf::program_header::PT_INTERP;
    use std::fs;

    let data = fs::read(path)
        .inspect_err(|e| error!("reading file error={e:?}"))
        .ok()?;
    let file_size = data.len();
    let elf = goblin::elf::Elf::parse(&data)
        .inspect_err(|e| error!("parsing ELF file error={e:?}"))
        .ok()?;
    elf.program_headers
        .into_iter()
        .find(|ph| ph.p_type == PT_INTERP)
        .map(|ph| {
            let start = ph.p_offset as usize;
            let size = ph.p_filesz as usize;
            let end = start.saturating_add(size);
            if end <= file_size {
                let raw = &data[start..end];
                let nul_pos = raw.iter().position(|&b| b == 0).unwrap_or(raw.len());
                Some(String::from_utf8_lossy(&raw[..nul_pos]).into_owned())
            } else {
                error!(
                    "interpreter format error, file_size={file_size} < ProgramHeader(start={start} + size={size} -> end={end})",
                );
                None
            }
        })?
}

#[cfg(target_os = "android")]
#[flutter_rust_bridge::frb(sync)]
pub fn load_library(lib_path: String) -> Result<(), String> {
    static GLOBAL_LIBRARIES: OnceLock<Mutex<HashMap<String, libloading::Library>>> =
        OnceLock::new();
    let container = GLOBAL_LIBRARIES.get_or_init(|| Mutex::new(HashMap::new()));

    let key = lib_path.clone();

    if container
        .lock()
        .map_err(|_| "mutex poisoned".to_string())?
        .contains_key(&key)
    {
        return Ok(());
    }

    let lib = unsafe { libloading::Library::new(&lib_path).map_err(|e| e.to_string())? };
    let mut guard = container.lock().map_err(|_| "mutex poisoned".to_string())?;
    guard.insert(key, lib);
    Ok(())
}

#[cfg(unix)]
#[flutter_rust_bridge::frb(sync)]
pub fn set_executable_permissions(exec: String) -> Result<(), String> {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    info!("exec={exec:?}");
    let meta = fs::metadata(&exec)
        .inspect_err(|e| error!("getting metadata error={e:?}"))
        .map_err(|e| e.to_string())?;
    let mut perms = meta.permissions();
    info!("current permissions={perms:?}");
    match perms.mode() & 0o111 {
        0o111 => {
            info!("executable already set");
            Ok(())
        }
        _ => {
            perms.set_mode(perms.mode() | 0o111);
            info!("setting permissions={perms:?}");
            fs::set_permissions(&exec, perms)
                .inspect_err(|e| error!("setting permissions error={e:?}"))
                .map_err(|e| e.to_string())
        }
    }
}

#[cfg(not(unix))]
#[flutter_rust_bridge::frb(sync)]
pub fn get_executable_interpreter(_path: &str) -> Option<String> {
    None
}

#[cfg(not(unix))]
#[flutter_rust_bridge::frb(sync)]
pub fn set_executable_permissions(_exec: String) -> Result<(), String> {
    Ok(())
}

#[allow(dead_code)]
fn extend_env(key: &str, paths_opt: Option<Vec<String>>) -> Option<String> {
    match paths_opt {
        Some(user_paths) => {
            info!("user provided {key}={user_paths:?}");

            let combined: Vec<std::path::PathBuf> = match std::env::var_os(key) {
                Some(existing) => {
                    info!("appending to existing {key}={existing:?}");
                    std::env::split_paths(&existing)
                        .chain(user_paths.iter().map(|p| std::path::PathBuf::from(p)))
                        .collect()
                }
                None => {
                    info!("not existing {key}, using user provided");
                    user_paths
                        .iter()
                        .map(|p| std::path::PathBuf::from(p))
                        .collect()
                }
            };

            match std::env::join_paths(combined) {
                Ok(joined) => {
                    info!("final {key}={joined:?}");
                    Some(joined.to_string_lossy().into_owned())
                }
                Err(e) => {
                    error!("join paths error={e:?}");
                    None
                }
            }
        }
        None => std::env::var_os(key).map(|v| v.to_string_lossy().into_owned()),
    }
}

pub async fn execute_command(
    mut exec: String,
    mut args: Vec<String>,
    env: Option<HashMap<String, String>>,
) -> Result<(String, String), String> {
    info!("Executing command exec={exec:?}, args={args:?}, env={env:?}");

    if std::path::Path::new(&exec).is_file() {
        // set_executable_permissions(exec.clone())?;
        let interpreter = get_executable_interpreter(&exec);
        if let Some(interpreter) = interpreter {
            info!("Using interpreter={interpreter} in exec={exec:?}");
            (exec, args) = (interpreter, vec![exec].into_iter().chain(args).collect())
        }
    }

    info!("internal Executing command exec={exec:?}, args={args:?}");
    let mut command = tokio::process::Command::new(&exec);
    command.args(&args);
    if let Some(env_map) = env {
        for (k, v) in env_map {
            info!("injecting env key={k:?}, value={v:?}",);
            command.env(k, v);
        }
    }
    let output = command.output().await.map_err(|e| e.to_string())?;
    Ok((
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    ))
}

pub async fn execute_python_script(
    exec: String,
    code: String,
    python_paths: Option<Vec<String>>,
    python_library_dir: Option<String>,
) -> Result<(String, String), String> {
    let env = match python_paths {
        Some(paths) => {
            let value =
                std::env::join_paths(paths).map_err(|e| format!("join paths error={e:?}"))?;
            Some(HashMap::from([(
                "PYTHONPATH".into(),
                value.to_string_lossy().into_owned(),
            )]))
        }
        None => None,
    };
    let env = match python_library_dir {
        Some(dir) => match env {
            Some(mut env) => {
                env.insert("LD_LIBRARY_PATH".into(), dir);
                Some(env)
            }
            None => Some(HashMap::from([("LD_LIBRARY_PATH".into(), dir)])),
        },
        None => None,
    };
    execute_command(exec, vec!["-c".to_string(), code], env).await
}

// pub async fn get_python_version_with_api(
//     python_paths: Option<Vec<String>>,
//     python_library_dir: Option<String>,
// ) -> Result<(String, String), String> {
//     let env = match python_paths {
//         Some(paths) => {
//             let value =
//                 std::env::join_paths(paths).map_err(|e| format!("join paths error={e:?}"))?;
//             Some(HashMap::from([(
//                 "PYTHONPATH".into(),
//                 value.to_string_lossy().into_owned(),
//             )]))
//         }
//         None => None,
//     };
//     let env = match python_library_dir {
//         Some(dir) => match env {
//             Some(mut env) => {
//                 env.insert("LD_LIBRARY_PATH".into(), dir);
//                 Some(env)
//             }
//             None => Some(HashMap::from([("LD_LIBRARY_PATH".into(), dir)])),
//         },
//         None => None,
//     };
//     execute_command(exec, vec!["-c".to_string(), code], env).await
// }
