local GLib = import("GLib")
local Gio = import("Gio")

class AssetLocator {
    source_root = null

    constructor(source_root = null) {
        this.source_root = source_root
    }

    function path_exists(path) {
        return path != null && Gio.File.new_for_path(path).query_exists(null)
    }

    function first_existing(paths) {
        foreach (path in paths) {
            if (this.path_exists(path)) return path
        }
        return null
    }

    function path(name) {
        local resources = GLib.getenv("SQGI_APP_RESOURCES")
        return this.first_existing([
            resources != null ? GLib.build_filenamev([resources, "assets", name]) : null,
            this.source_root != null ? GLib.build_filenamev([this.source_root, "assets", name]) : null,
            GLib.build_filenamev(["assets", name])
        ])
    }
}

return {
    AssetLocator = AssetLocator
}
