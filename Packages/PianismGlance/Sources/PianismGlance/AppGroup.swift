/// The App Group the app and the widget extension share files through (ADR 0003, ADR 0010).
public enum AppGroup {
    /// Must match the group in `Config/Pianism.entitlements` and `Config/Widgets.entitlements`: a process
    /// outside it has no container, so it can neither write nor read the files.
    public static let identifier = "group.com.edkarabinus.Pianism"
}
