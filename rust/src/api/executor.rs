#[allow(unused_imports)]
use log::{error, info};
#[allow(unused_imports)]
use std::sync::{Mutex, OnceLock};
use std::collections::HashMap;

#[cfg(target_os = "android")]
#[flutter_rust_bridge::frb(sync)]
fn get_executable_interpreter(path: &str) -> Option<String> {
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
    perms.set_mode(perms.mode() | 0o111);
    info!("setting permissions={perms:?}");
    fs::set_permissions(&exec, perms)
        .inspect_err(|e| error!("setting permissions error={e:?}"))
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[allow(dead_code)]
fn extend_env(key: &str, ld_library_path: Option<Vec<String>>) -> Option<String> {
    match ld_library_path {
        Some(paths1) => {
            info!("user provided {key}={paths1:?}");

            let paths = match std::env::var(key) {
                Ok(value) => {
                    info!("appending to existing {key}={value}");
                    let paths0 = value.split(":").map(|s| s.to_string()).collect::<Vec<_>>();
                    let paths = paths0.into_iter().chain(paths1).collect::<Vec<_>>();
                    paths
                }
                Err(_) => {
                    info!("not existing {key}, using user provided");
                    paths1
                }
            };
            info!("final {key}={paths:?}");
            Some(paths.join(":"))
        }
        None => std::env::var(key).ok(),
    }
}

#[allow(unused_mut)]
pub async fn execute_command(
    mut exec: String,
    mut args: Vec<String>,
    ld_library_path: Option<Vec<String>>,
    env: Option<HashMap<String, String>>,
) -> Result<(String, String), String> {
    info!("Executing command exec={exec:?}, args={args:?}, ld_library_path={ld_library_path:?}");

    let ld_library_path_key = "LD_LIBRARY_PATH";
    #[allow(unused_assignments)]
    let mut ld_library_path_value: Option<String> = None;
    #[cfg(unix)]
    {
        set_executable_permissions(exec.clone())?;

        ld_library_path_value = extend_env(ld_library_path_key, ld_library_path);

        let interpreter = get_executable_interpreter(&exec);
        if let Some(interpreter) = interpreter {
            info!("Using interpreter={interpreter} in exec={exec:?}");
            (exec, args) = (interpreter, vec![exec].into_iter().chain(args).collect())
        }
    }

    #[cfg(not(unix))]
    {
        ld_library_path_value = None;
    }

    info!("internal Executing command exec={exec:?}, args={args:?}");
    let mut command = tokio::process::Command::new(&exec);
    command.args(&args);
    if let Some(ld_library_path_value) = ld_library_path_value {
        command.env(ld_library_path_key, ld_library_path_value);
    }
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
    execute_command(
        exec,
        vec!["-c".to_string(), code],
        python_library_dir.map(|dir| vec![dir]),
        python_paths.map(|paths| HashMap::from([("PYTHONPATH".to_string(), paths.join(":"))])),
    )
    .await
}
