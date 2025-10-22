#[flutter_rust_bridge::frb(sync)]
pub fn set_env(key: String, value: String) {
    std::env::set_var(key, value);
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_env(key: String) -> String {
    std::env::var(key).unwrap_or_default()
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_paths_env(key: String, separator: String) -> Vec<String> {
    std::env::var(key).unwrap_or_default().split(&separator).map(|s| s.to_string()).collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_or_append_paths_env(key: String, paths: Vec<String>, separator: String) {
    let mut paths0 = get_paths_env(key.clone(), separator.clone());
    // collect first to avoid holding an immutable borrow of `paths0` during extend
    let paths1: Vec<String> = paths
        .into_iter()
        .filter(|p| !paths0.contains(p))
        .collect();
    paths0.extend(paths1);
    set_env(key, paths0.join(&separator));
}
