
pub fn init_logger() {
    #[cfg(target_os = "android")]
    {
        use android_logger::Config;
        use log::LevelFilter;

        android_logger::init_once(
            Config::default()
                .with_max_level(LevelFilter::Trace)
                .with_tag("rust_lib_integrate_python_demo"),
        );
    }

    #[cfg(not(target_os = "android"))]
    {
        let _ = env_logger::Builder::from_env(
            env_logger::Env::default().default_filter_or("trace"),
        )
        .try_init();
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    init_logger();
}
