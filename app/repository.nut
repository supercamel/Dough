local GLib = import("GLib")
local Gio = import("Gio")
local Spino = import("Spino", "1.2")

local Models = import("models.nut")

function table_get(t, key, fallback = null) {
    if (t != null && key in t) return t[key]
    return fallback
}

function tutorial_state_from_table(t) {
    return {
        completed = table_get(t, "completed", false),
        dismissed = table_get(t, "dismissed", false),
        last_step = table_get(t, "last_step", 0)
    }
}

class SpinodbRepository {
    db_path = ""
    journal_path = ""
    db = null
    state = null

    constructor(db_path = null) {
        this.db_path = db_path != null ? db_path : this.default_db_path()
        this.journal_path = this.db_path + ".journal"
        this.open()
    }

    function default_db_path() {
        return GLib.build_filenamev([GLib.get_user_data_dir(), "dough", "dough.spino"])
    }

    function ensure_storage_dir() {
        local dir = Gio.File.new_for_path(this.db_path).get_parent()
        if (dir != null && !dir.query_exists(null))
            dir.make_directory(null)
    }

    function open() {
        this.ensure_storage_dir()
        this.db = Spino.Database.new()

        if (Gio.File.new_for_path(this.db_path).query_exists(null))
            this.db.load(this.db_path)

        this.db.enable_journal(this.journal_path)
        this.state = this.db.get_collection("state")
        this.state.create_index("kind")
    }

    function load_document() {
        local row = this.state.find_one("{kind:\"current\"}")
        if (row != null && row.len() > 0)
            return Models.document_from_table(sqgi.json.parse(row))

        local doc = Models.DoughDocument()
        doc.title = "New Budget"
        doc.regenerate_periods()
        this.save_document(doc)
        return doc
    }

    function save_document(doc) {
        local data = doc.to_table()
        data.kind <- "current"
        this.state.upsert("{kind:\"current\"}", sqgi.json.stringify(data))
        this.db.save(this.db_path)
    }

    function load_tutorial_state() {
        local row = this.state.find_one("{kind:\"tutorial\"}")
        if (row != null && row.len() > 0)
            return tutorial_state_from_table(sqgi.json.parse(row))

        return tutorial_state_from_table(null)
    }

    function save_tutorial_state(tutorial_state) {
        local data = tutorial_state_from_table(tutorial_state)
        data.kind <- "tutorial"
        this.state.upsert("{kind:\"tutorial\"}", sqgi.json.stringify(data))
        this.db.save(this.db_path)
    }

    function reset_with_sample() {
        local doc = Models.sample_document()
        this.save_document(doc)
        return doc
    }
}

return {
    SpinodbRepository = SpinodbRepository
}
