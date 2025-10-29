use log::{error, info};

#[allow(dead_code)]
pub(crate) trait EnvExt {
    /// set the env[key] to the given value
    fn env_set_paths<S, I>(&mut self, key: S, paths: I) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
        I: IntoIterator<Item = S>;

    /// push the given value to the existing env[key],
    ///  if env[key] is not set, this equals to env_set_paths
    ///  if the given value is already in the env[key], it will be ignored
    fn env_push_path<S>(&mut self, key: S, path: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>;

    /// pop the last value from the existing env[key]
    fn env_remove_path<S>(&mut self, key: S, value: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>;
}

impl EnvExt for std::process::Command {
    fn env_set_paths<S, I>(&mut self, key: S, paths: I) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
        I: IntoIterator<Item = S>,
    {
        match std::env::join_paths(paths) {
            Ok(value) => self.env(key.as_ref(), value),
            Err(e) => {
                error!("join paths error={e:?}");
                return self;
            }
        }
    }

    fn env_push_path<S>(&mut self, key: S, path: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
    {
        let key_ref = key.as_ref();
        let path_ref = path.as_ref();

        match std::env::var_os(key_ref) {
            Some(origin_value) => {
                match std::env::join_paths(
                    std::env::split_paths(&origin_value)
                        .filter(|p| p.as_os_str() != path_ref)
                        .chain(std::iter::once(std::path::PathBuf::from(path_ref))),
                ) {
                    Ok(value) => {
                        info!("setting key={key_ref:?} value={value:?}");
                        self.env(key, value)
                    }
                    Err(e) => {
                        error!("join paths error={e:?}, key={key_ref:?}, value={path_ref:?}");
                        self
                    }
                }
            }
            None => {
                info!("key={key_ref:?} not set, using user provided");
                self.env(key, path)
            }
        }
    }

    fn env_remove_path<S>(&mut self, key: S, value: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
    {
        let key_ref = key.as_ref();
        let value_ref = value.as_ref();

        match std::env::var_os(key_ref) {
            Some(origin_value) => {
                match std::env::join_paths(
                    std::env::split_paths(&origin_value).filter(|p| p.as_os_str() != value_ref),
                ) {
                    Ok(value) => {
                        info!("setting key={key_ref:?} value={value:?}");
                        self.env(key, value)
                    }
                    Err(e) => {
                        unreachable!(
                            "join paths error={e:?}, key={key_ref:?}, value={value_ref:?}"
                        );
                    }
                }
            }
            None => self,
        }
    }
}

impl EnvExt for tokio::process::Command {
    fn env_set_paths<S, I>(&mut self, key: S, paths: I) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
        I: IntoIterator<Item = S>,
    {
        match std::env::join_paths(paths) {
            Ok(path) => self.env(key.as_ref(), path),
            Err(e) => {
                error!("join paths error={e:?}");
                return self;
            }
        }
    }

    fn env_push_path<S>(&mut self, key: S, path: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
    {
        let key_ref = key.as_ref();
        let value_ref = path.as_ref();

        match std::env::var_os(key_ref) {
            Some(origin_value) => match std::env::join_paths(
                std::env::split_paths(&origin_value)
                    .filter(|p| p.as_os_str() != value_ref)
                    .chain(std::iter::once(std::path::PathBuf::from(value_ref))),
            ) {
                Ok(joined) => self.env(key, joined),
                Err(e) => {
                    error!("join paths error={e:?}, key={key_ref:?}, value={value_ref:?}");
                    self
                }
            },
            None => {
                info!("key={key_ref:?} not set, using user provided");
                self.env(key, path)
            }
        }
    }

    fn env_remove_path<S>(&mut self, key: S, value: S) -> &mut Self
    where
        S: AsRef<std::ffi::OsStr>,
    {
        let key_ref = key.as_ref();
        let value_ref = value.as_ref();

        match std::env::var_os(key_ref) {
            Some(origin_value) => match std::env::join_paths(
                std::env::split_paths(&origin_value).filter(|p| p.as_os_str() != value_ref),
            ) {
                Ok(joined) => self.env(key_ref, joined),
                Err(e) => {
                    error!("join paths error={e:?}, key={key_ref:?}, value={value_ref:?}");
                    self
                }
            },
            None => self,
        }
    }
}
