pub fn init_logger() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    let _ = flexi_logger::Logger::try_with_str("trace")
        .unwrap()
        .duplicate_to_stdout(flexi_logger::Duplicate::All)
        .log_to_file(flexi_logger::FileSpec::default().directory("logs"))
        .start()
        .unwrap();
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    init_logger();
}
