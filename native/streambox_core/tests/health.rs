use streambox_core::{health, platform_info, version};

#[test]
fn exposes_phase_one_core_identity() {
    assert_eq!(version(), "streambox-core 0.1.0");
    assert!(health().native_core_available);
    assert_eq!(health().api_version, "0.1.0");
    assert!(!platform_info().target_os.is_empty());
}
