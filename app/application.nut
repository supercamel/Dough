local GLib = import("GLib")
local Gio = import("Gio")
local Gdk = import("Gdk", "4.0")
local Gtk = import("Gtk", "4.0")
local cairo = import("cairo")

local Assets = import("assets.nut")
local Models = import("models.nut")
local Repository = import("repository.nut")
local Helpers = import("ui_helpers.nut")

class DoughApplication {
    app = null
    repository = null
    document = null
    assets = null
    ui = null
    window = null
    title_label = null
    date_label = null
    dashboard_area = null
    status_label = null
    active_file_chooser = null
    smoke_test = false

    constructor(options = null) {
        this.smoke_test = options != null && "smoke" in options ? options.smoke : false
        this.assets = Assets.AssetLocator()
        this.ui = Helpers.WidgetFactory(this.assets)
        this.repository = Repository.SpinodbRepository()
        this.document = this.repository.load_document()
        this.repair_transaction_envelope_paths()
        this.app = Gtk.Application.new("dev.sam.dough", Gio.ApplicationFlags.flags_none)
    }

    function run(argc, argv) {
        local self = this
        this.app.connect("activate", function() { self.activate() })
        local status = this.app.run(argc, argv)
        print("Application exited with status " + status + "\n")
        return status
    }

    function activate() {
        this.configure_app_icon()

        this.window = Gtk.ApplicationWindow.new(this.app)
        this.window.set_default_size(1100, 760)
        this.window.set_title("Dough")

        local header = Gtk.HeaderBar.new()
        header.set_title_widget(Gtk.Label.new("Dough"))
        header.pack_end(this.ui.plain_button("About", function() { this.show_about() }.bindenv(this)))
        header.pack_end(this.ui.plain_button("Quit", function() { this.quit() }.bindenv(this)))
        this.window.set_titlebar(header)

        local root = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        root.append(this.build_dashboard())

        this.status_label = Gtk.Label.new("Spinodb: " + this.repository.db_path)
        this.status_label.set_xalign(0.0)
        this.status_label.add_css_class("dim-label")
        this.status_label.set_margin_top(6)
        this.status_label.set_margin_bottom(6)
        this.status_label.set_margin_start(10)
        this.status_label.set_margin_end(10)
        root.append(this.status_label)

        this.window.set_child(root)
        this.refresh_title()
        this.window.present()

        if (this.smoke_test) this.run_smoke_test()
    }

    function money(value) {
        return this.document.currency + format("%.2f", value)
    }

    function amount_text(value) {
        return format("%.2f", value)
    }

    function parse_amount(text) {
        if (text == null || text.len() == 0) return null
        try {
            return text.tofloat()
        } catch (e) {
            return null
        }
    }

    function set_status(text) {
        if (this.status_label != null) this.status_label.set_text(text)
        print(text + "\n")
    }

    function configure_app_icon() {
        local icon_path = this.assets.path("icon.png")
        if (icon_path == null) return

        local display = Gdk.Display.get_default()
        if (display != null) {
            local theme = Gtk.IconTheme.get_for_display(display)
            theme.add_search_path(GLib.path_get_dirname(icon_path))
        }

        local basename = GLib.path_get_basename(icon_path)
        local dot = basename.find(".")
        local icon_name = dot == null ? basename : basename.slice(0, dot)
        Gtk.Window.set_default_icon_name(icon_name)
    }

    function refresh_title() {
        if (this.window != null) this.window.set_title("Dough - " + this.document.title)
        if (this.title_label != null) this.title_label.set_text(this.document.title)
        if (this.date_label != null) this.date_label.set_text(this.document.current_period())
        if (this.dashboard_area != null) this.dashboard_area.queue_draw()
    }

    function persist_document(status = null) {
        this.repository.save_document(this.document)
        this.refresh_title()
        if (status != null) this.set_status(status)
    }

    function make_id(prefix) {
        return prefix + "-" + GLib.get_monotonic_time()
    }

    function first_account_id() {
        return this.document.accounts.len() == 0 ? "" : this.document.accounts[0].id
    }

    function account_label(account) {
        if (account == null) return "No account"
        local name = account.name.len() > 0 ? account.name : "Unnamed account"
        if (account.number.len() > 0) return name + " - " + account.number
        return name
    }

    function account_name_for(id) {
        local account = this.document.find_account(id)
        if (account != null) return this.account_label(account)
        return id != null && id.len() > 0 ? id : "No account"
    }

    function account_options(include_all = false, include_none = false) {
        local ids = []
        local labels = []
        if (include_all) {
            ids.push("")
            labels.push("All accounts")
        }
        if (include_none) {
            ids.push("")
            labels.push("No account")
        }
        foreach (account in this.document.accounts) {
            ids.push(account.id)
            labels.push(this.account_label(account))
        }
        if (ids.len() == 0) {
            ids.push("")
            labels.push("No accounts")
        }
        return { ids = ids, labels = labels }
    }

    function index_for_value(values, value, fallback = 0) {
        for (local i = 0; i < values.len(); i = i + 1) {
            if (values[i] == value) return i
        }
        return fallback
    }

    function dropdown_value(values, dropdown, fallback = "") {
        local index = dropdown.get_selected()
        if (index < 0 || index >= values.len()) return fallback
        return values[index]
    }

    function envelope_path(folder_id, envelope_id) {
        if (folder_id == null || envelope_id == null) return ""
        if (folder_id.len() == 0 || envelope_id.len() == 0) return ""
        return folder_id + "/" + envelope_id
    }

    function envelope_options(type) {
        local paths = []
        local labels = []
        if (type == "transfer") {
            paths.push("")
            labels.push("No envelope")
            return { paths = paths, labels = labels }
        }

        foreach (folder in this.document.folders_for_type(type)) {
            foreach (envelope in folder.envelopes) {
                local label = folder.name + " / " + envelope.name
                if (folder.hidden || envelope.hidden) label += " (hidden)"
                paths.push(folder.id + "/" + envelope.id)
                labels.push(label)
            }
        }

        if (paths.len() == 0) {
            local path = this.ensure_envelope_path(type)
            paths.push(path.folder_id + "/" + path.envelope_id)
            labels.push(path.name)
        }

        return { paths = paths, labels = labels }
    }

    function type_label(type) {
        if (type == "income") return "Income"
        if (type == "expense") return "Expense"
        if (type == "transfer") return "Transfer"
        return type
    }

    function transaction_account_label(txn) {
        if (txn.type == "transfer" && txn.transfer_account_id.len() > 0)
            return this.account_name_for(txn.account_id) + " -> " + this.account_name_for(txn.transfer_account_id)
        return this.account_name_for(txn.account_id)
    }

    function transaction_envelope_label(txn) {
        if (txn.type == "transfer") return "Transfer"
        local folder = this.document.folder_label(txn.type, txn.folder_id)
        local envelope = this.document.envelope_label(txn.type, txn.folder_id, txn.envelope_id, "")
        if (folder.len() > 0 && envelope.len() > 0) return folder + " / " + envelope
        if (folder.len() > 0) return folder
        if (txn.folder_id.len() > 0 || txn.envelope_id.len() > 0)
            return "Missing envelope (" + txn.folder_id + "/" + txn.envelope_id + ")"
        return "Unassigned"
    }

    function transaction_amount_label(txn) {
        local prefix = txn.type == "income" ? "+" : "-"
        if (txn.type == "transfer") prefix = "-"
        return prefix + this.money(txn.amount)
    }

    function labeled_control(label_text, control) {
        local row = Gtk.Box.new(Gtk.Orientation.horizontal, 10)
        local label = Gtk.Label.new(label_text)
        label.set_xalign(0.0)
        label.set_size_request(120, -1)
        row.append(label)
        control.set_hexpand(true)
        row.append(control)
        return row
    }

    function first_envelope_path(type) {
        local folders = this.document.folders_for_type(type)
        foreach (folder in folders) {
            foreach (envelope in folder.envelopes) {
                if (!folder.hidden && !envelope.hidden) {
                    return {
                        type = type,
                        folder_id = folder.id,
                        envelope_id = envelope.id,
                        name = envelope.name
                    }
                }
            }
        }
        return { type = type, folder_id = "", envelope_id = "", name = "" }
    }

    function fallback_envelope_name(type) {
        return type == "income" ? "Uncategorized Income" : "Uncategorized Expense"
    }

    function ensure_envelope_path(type, folder_id = "", envelope_id = "", fallback_name = null) {
        if (type == "transfer")
            return { type = "transfer", folder_id = "", envelope_id = "", name = "Transfer", created = false }

        local requested_folder_id = folder_id == null ? "" : folder_id
        local requested_envelope_id = envelope_id == null ? "" : envelope_id
        local existing = this.document.find_envelope(type, requested_folder_id, requested_envelope_id)
        if (existing != null) {
            return {
                type = type,
                folder_id = requested_folder_id,
                envelope_id = requested_envelope_id,
                name = existing.name,
                created = false
            }
        }

        if (requested_folder_id.len() == 0 || requested_envelope_id.len() == 0) {
            local first = this.first_envelope_path(type)
            if (first.envelope_id.len() > 0) {
                return {
                    type = first.type,
                    folder_id = first.folder_id,
                    envelope_id = first.envelope_id,
                    name = first.name,
                    created = false
                }
            }
        }

        local folder = requested_folder_id.len() > 0 ?
            this.document.find_folder(type, requested_folder_id) : null
        local created = false
        if (folder == null) {
            folder = Models.EnvelopeFolder(
                requested_folder_id.len() > 0 ? requested_folder_id : this.make_id(type + "-folder"),
                type == "income" ? "Imported Income" : "Imported Expenses",
                type)
            if (type == "income") this.document.add_income_folder(folder)
            else this.document.add_expense_folder(folder)
            created = true
        }

        local envelope_name = fallback_name != null && fallback_name.len() > 0 ?
            fallback_name : this.fallback_envelope_name(type)
        local envelope = Models.Envelope(
            requested_envelope_id.len() > 0 ? requested_envelope_id : this.make_id("env"),
            envelope_name,
            "Created to repair a transaction envelope assignment")
        folder.add_envelope(envelope)

        return {
            type = type,
            folder_id = folder.id,
            envelope_id = envelope.id,
            name = envelope.name,
            created = true
        }
    }

    function import_rule_envelope_path(rule, fallback_type) {
        if (rule == null) return this.ensure_envelope_path(fallback_type)
        local type = rule.type.len() > 0 ? rule.type : fallback_type
        return this.ensure_envelope_path(type, rule.folder_id, rule.envelope_id, rule.name)
    }

    function repair_transaction_envelope_paths() {
        local repaired = 0
        foreach (txn in this.document.transactions) {
            if (txn.type == "transfer") continue
            if (this.document.find_envelope(txn.type, txn.folder_id, txn.envelope_id) == null) {
                local path = this.ensure_envelope_path(txn.type, txn.folder_id, txn.envelope_id, txn.description)
                txn.type = path.type
                txn.folder_id = path.folder_id
                txn.envelope_id = path.envelope_id
                repaired = repaired + 1
            }

            foreach (split in txn.splits) {
                if (this.document.find_envelope(txn.type, split.folder_id, split.envelope_id) == null) {
                    local split_path = this.ensure_envelope_path(txn.type, split.folder_id, split.envelope_id, split.description)
                    split.folder_id = split_path.folder_id
                    split.envelope_id = split_path.envelope_id
                    repaired = repaired + 1
                }
            }
        }
        if (repaired > 0) this.repository.save_document(this.document)
        return repaired
    }

    function ensure_folder_for_type(type) {
        local folders = this.document.folders_for_type(type)
        if (folders.len() > 0) return folders[0]

        local folder = Models.EnvelopeFolder(this.make_id(type + "-folder"),
            type == "income" ? "Income" : "Expenses", type)
        if (type == "income") this.document.add_income_folder(folder)
        else this.document.add_expense_folder(folder)
        return folder
    }

    function create_envelope_and_budget(type) {
        local folder = this.ensure_folder_for_type(type)
        local envelope = Models.Envelope(this.make_id("env"), "New Envelope", "")
        folder.add_envelope(envelope)

        return this.create_budget_for_envelope(type, folder, envelope)
    }

    function create_budget_for_envelope(type, folder, envelope) {
        local budget = Models.BudgetEnvelope(
            this.make_id("budget"),
            envelope.name,
            0.0,
            0.0,
            type,
            folder.id,
            envelope.id,
            this.document.current_period())
        this.document.add_budget(budget)
        return budget
    }

    function default_export_path(name) {
        return GLib.build_filenamev([GLib.get_user_data_dir(), "dough", name])
    }

    function export_graph_png(path, pie_chart = false) {
        if (path == null || path.len() == 0) {
            this.set_status("Enter a PNG path before exporting.")
            return
        }

        local surface = cairo.image_surface_create(cairo.Format.argb32, 900, 560)
        local cr = cairo.Context.create(surface)
        if (pie_chart) this.draw_pie_chart(cr, 900, 560)
        else this.draw_graph(cr, 900, 560)
        surface.write_to_png(path)
        this.set_status("Exported graph to " + path)
    }

    function clear_listbox(list) {
        local child = list.get_first_child()
        while (child != null) {
            list.remove(child)
            child = list.get_first_child()
        }
    }

    function remove_array_item_by_id(items, id) {
        for (local i = items.len() - 1; i >= 0; i = i - 1) {
            if (items[i].id == id) items.remove(i)
        }
    }

    function scan_lines(text) {
        local out = []
        local start = 0
        while (start < text.len()) {
            local end = text.find("\n", start)
            if (end == null) end = text.len()
            local line = text.slice(start, end)
            if (line.len() > 0 && line.slice(line.len() - 1, line.len()) == "\r")
                line = line.slice(0, line.len() - 1)
            out.push(line)
            start = end + 1
        }
        return out
    }

    function is_space(ch) {
        return ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
    }

    function trim(text) {
        if (text == null) return ""
        local start = 0
        local end = text.len()
        while (start < end && this.is_space(text.slice(start, start + 1))) start = start + 1
        while (end > start && this.is_space(text.slice(end - 1, end))) end = end - 1
        return text.slice(start, end)
    }

    function parse_import_amount(text) {
        if (text == null) return null
        local cleaned = ""
        local negative = false
        for (local i = 0; i < text.len(); i = i + 1) {
            local ch = text.slice(i, i + 1)
            if (ch == "-" || ch == "(") negative = true
            else if ((ch >= "0" && ch <= "9") || ch == ".") cleaned += ch
        }
        if (cleaned.len() == 0) return null
        try {
            local value = cleaned.tofloat()
            if (negative && value > 0.0) value = value * -1.0
            return value
        } catch (e) {
            return null
        }
    }

    function parse_column_index(text, fallback = -1) {
        local trimmed = this.trim(text)
        if (trimmed.len() == 0) return fallback
        try {
            return trimmed.tointeger()
        } catch (e) {
            return fallback
        }
    }

    function csv_field(row, index) {
        if (index == null || index < 0 || index >= row.len()) return ""
        return row[index]
    }

    function parse_csv_line(line) {
        local fields = []
        local field = ""
        local quoted = false
        local i = 0
        while (i < line.len()) {
            local ch = line.slice(i, i + 1)
            if (quoted) {
                if (ch == "\"") {
                    local next_ch = i + 1 < line.len() ? line.slice(i + 1, i + 2) : ""
                    if (next_ch == "\"") {
                        field += "\""
                        i = i + 2
                        continue
                    }
                    quoted = false
                } else {
                    field += ch
                }
            } else if (ch == "\"") {
                quoted = true
            } else if (ch == ",") {
                fields.push(this.trim(field))
                field = ""
            } else {
                field += ch
            }
            i = i + 1
        }
        fields.push(this.trim(field))
        return fields
    }

    function regex_matches(pattern, text) {
        if (pattern == null || pattern.len() == 0) return false
        try {
            local regex = GLib.Regex.new(pattern,
                GLib.RegexCompileFlags.default,
                GLib.RegexMatchFlags.default)
            local got = regex.match(text, GLib.RegexMatchFlags.default)
            if (typeof(got) == "bool") return got
            if (typeof(got) == "array" && got.len() >= 1) return got[0] == true
            if (typeof(got) == "string") return got.len() > 0
            if (typeof(got) == "instance") return got.matches()
        } catch (e) {
            return false
        }
        return false
    }

    function match_import_rule(description, type) {
        local haystack = description == null ? "" : description
        local best = null
        local best_priority = 2147483647
        foreach (rule in this.document.import_rules) {
            if (!rule.enabled) continue
            if (rule.type != type) continue
            if (rule.priority >= best_priority) continue
            if (this.regex_matches(rule.pattern, haystack)) {
                best = rule
                best_priority = rule.priority
            }
        }
        return best
    }

    function imported_transaction(date, description, signed_amount, account_id = null) {
        local amount = signed_amount
        if (amount == null) return null

        local type = amount < 0.0 ? "expense" : "income"
        if (amount < 0.0) amount = amount * -1.0
        local rule = this.match_import_rule(description, type)
        local path_info = this.import_rule_envelope_path(rule, type)

        return Models.Transaction(
            this.make_id("import"),
            account_id != null && account_id.len() > 0 ? account_id : this.first_account_id(),
            date != null && date.len() > 0 ? date : this.document.start_date,
            path_info.type,
            path_info.folder_id,
            path_info.envelope_id,
            description,
            amount)
    }

    function refresh_budget_summary(labels, area = null) {
        labels.income.set_text("Income " + this.money(this.document.total_budgeted("income")))
        labels.expenses.set_text("Expenses " + this.money(this.document.total_budgeted("expense")))
        local reserve = this.document.reserve_enabled ? this.document.reserve_amount : 0.0
        labels.reserve.set_text("Reserve " + this.money(reserve))
        labels.unallocated.set_text("Unallocated " + this.money(this.document.unallocated_amount()))
        if (area != null) area.queue_draw()
    }

    function build_dashboard() {
        local root = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        local toolbar = Gtk.Box.new(Gtk.Orientation.horizontal, 6)
        toolbar.set_margin_top(8)
        toolbar.set_margin_bottom(8)
        toolbar.set_margin_start(8)
        toolbar.set_margin_end(8)

        toolbar.append(this.ui.action_button("New", "icon.png", function() { this.new_document() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Sample", "report.png", function() { this.load_sample_document() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Accounts", "books.png", function() { this.show_accounts() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Transactions", "report.png", function() { this.show_transactions() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Import", "report.png", function() { this.show_import_options() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Budget", "budget.png", function() { this.show_budget() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Report", "report.png", function() { this.show_budget_report() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Envelopes", "envelope.png", function() { this.show_envelopes() }.bindenv(this)))
        toolbar.append(this.ui.action_button("Line", "linegraph.png", function() { this.show_graph("Line Graphs", "linegraph.png") }.bindenv(this)))
        toolbar.append(this.ui.action_button("Pie", "piechart.png", function() { this.show_graph("Pie Charts", "piechart.png") }.bindenv(this)))
        toolbar.append(this.ui.action_button("Options", "interface.png", function() { this.show_options() }.bindenv(this)))
        root.append(toolbar)

        local head = this.ui.padded_box(Gtk.Orientation.vertical, 8, 14)
        this.title_label = this.ui.label(this.document.title, "title-1")
        head.append(this.title_label)

        local nav = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        nav.append(this.ui.plain_button("<", function() { this.previous_period() }.bindenv(this)))
        this.date_label = Gtk.Label.new(this.document.current_period())
        this.date_label.set_hexpand(true)
        nav.append(this.date_label)
        nav.append(this.ui.plain_button(">", function() { this.next_period() }.bindenv(this)))
        head.append(nav)
        root.append(head)

        local scroll = Gtk.ScrolledWindow.new()
        scroll.set_vexpand(true)
        this.dashboard_area = Gtk.DrawingArea.new()
        this.dashboard_area.set_size_request(720, 360)
        this.dashboard_area.set_draw_func(function(area, cr, width, height) {
            this.draw_dashboard(cr, width, height)
        }.bindenv(this), null, function(_) {})
        scroll.set_child(this.dashboard_area)
        root.append(scroll)
        return root
    }

    function draw_dashboard(cr, width, height) {
        cr.set_source_rgb(0.95, 0.95, 0.93)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        if (this.document.budgets.len() == 0) {
            cr.set_source_rgb(0.10, 0.12, 0.13)
            cr.select_font_face("Sans", 0, 1)
            cr.set_font_size(26)
            cr.move_to(48, 70)
            cr.show_text("Welcome")
            cr.select_font_face("Sans", 0, 0)
            cr.set_font_size(15)
            cr.move_to(48, 120)
            cr.show_text("Add budget envelopes to begin tracking this period.")
            return
        }

        local y = 44.0
        foreach (item in this.document.budgets) {
            local spent = this.document.budget_spent(item)
            local pct = item.budgeted == 0.0 ? 0.0 : spent / item.budgeted
            if (pct > 1.0) pct = 1.0
            if (pct < 0.0) pct = 0.0

            local bar_width = width - 190
            local filled_width = bar_width * pct

            cr.set_source_rgb(0.18, 0.20, 0.20)
            cr.select_font_face("Sans", 0, 1)
            cr.set_font_size(14)
            cr.move_to(40, y)
            cr.show_text(this.document.budget_name(item))

            cr.set_source_rgba(0.15, 0.16, 0.16, 0.18)
            cr.rectangle(40, y + 14, bar_width, 22)
            cr.fill()

            if (spent > item.budgeted) cr.set_source_rgba(0.74, 0.16, 0.15, 0.82)
            else if (pct > 0.85) cr.set_source_rgba(0.76, 0.45, 0.12, 0.82)
            else cr.set_source_rgba(0.16, 0.50, 0.38, 0.82)
            cr.rectangle(40, y + 14, filled_width, 22)
            cr.fill()

            cr.set_source_rgb(0.18, 0.20, 0.20)
            cr.select_font_face("Sans", 0, 0)
            cr.set_font_size(13)
            cr.move_to(width - 130, y + 31)
            cr.show_text(this.money(item.remaining(spent)))
            y = y + 64
        }
    }

    function show_window(title, child, width = 820, height = 560) {
        local win = Gtk.ApplicationWindow.new(this.app)
        win.set_title(title)
        win.set_default_size(width, height)

        local header = Gtk.HeaderBar.new()
        header.set_title_widget(Gtk.Label.new(title))
        header.pack_end(this.ui.plain_button("Close", function() { win.close() }))
        win.set_titlebar(header)

        win.set_child(child)
        win.set_transient_for(this.window)
        win.present()
        return win
    }

    function module_window(title, details, icon_name) {
        local root = this.ui.padded_box(Gtk.Orientation.vertical, 16, 18)
        local hero = Gtk.Box.new(Gtk.Orientation.horizontal, 14)
        hero.append(this.ui.image(icon_name, 42))

        local copy = Gtk.Box.new(Gtk.Orientation.vertical, 4)
        copy.append(this.ui.label(title, "title-2"))
        local desc = this.ui.label(details, "dim-label")
        desc.set_wrap(true)
        copy.append(desc)
        hero.append(copy)
        root.append(hero)
        return root
    }

    function add_empty_list_row(list, text) {
        local row = Gtk.ListBoxRow.new()
        local label = this.ui.label(text, "dim-label")
        label.set_margin_top(14)
        label.set_margin_bottom(14)
        label.set_margin_start(12)
        label.set_margin_end(12)
        row.set_child(label)
        list.append(row)
    }

    function show_accounts() {
        local root = this.module_window(
            "Accounts",
            "Account setup and opening balances.",
            "books.png")

        root.append(this.ui.label("Accounts", "title-3"))
        local list_data = this.ui.scrolled_list()
        if (this.document.accounts.len() == 0)
            this.add_empty_list_row(list_data.list, "No accounts yet.")
        else
            foreach (account in this.document.accounts)
                this.add_account_editor_row(list_data.list, account)
        root.append(list_data.scroll)

        local account_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        account_actions.append(this.ui.plain_button("Add Account", function() {
            if (this.document.accounts.len() == 0) this.clear_listbox(list_data.list)
            local id = this.make_id("account")
            local account = Models.Account(id, "New Account", "", 0.0)
            this.document.add_account(account)
            local name_entry = this.add_account_editor_row(list_data.list, account)
            name_entry.grab_focus()
            this.persist_document("Added account and stored it in Spinodb.")
        }.bindenv(this)))
        account_actions.append(this.ui.plain_button("Transactions", function() {
            this.show_transactions()
        }.bindenv(this)))
        root.append(account_actions)

        this.show_window("Accounts", root, 900, 420)
    }

    function show_transactions() {
        local root = this.module_window(
            "Transactions",
            "Review, filter, import, and export transactions.",
            "report.png")

        local filter_box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local search_entry = Gtk.Entry.new()
        search_entry.set_hexpand(true)
        search_entry.set_placeholder_text("Search transactions")
        local start_entry = Gtk.Entry.new()
        start_entry.set_placeholder_text("Start date")
        local end_entry = Gtk.Entry.new()
        end_entry.set_placeholder_text("End date")
        local account_filter = this.account_options(true, false)
        local account_filter_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_filter.labels), null)
        local type_filter_values = ["", "income", "expense", "transfer"]
        local type_filter_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["All types", "Income", "Expense", "Transfer"]), null)
        local path_filter_entry = Gtk.Entry.new()
        path_filter_entry.set_placeholder_text("Envelope")
        filter_box.append(search_entry)
        filter_box.append(start_entry)
        filter_box.append(end_entry)
        filter_box.append(account_filter_dropdown)
        filter_box.append(type_filter_dropdown)
        filter_box.append(path_filter_entry)
        root.append(filter_box)

        local txn_data = this.ui.scrolled_list()
        root.append(txn_data.scroll)

        local refresh_transactions = function() {
            this.populate_transaction_rows(
                txn_data.list,
                search_entry.get_text(),
                start_entry.get_text(),
                end_entry.get_text(),
                this.dropdown_value(account_filter.ids, account_filter_dropdown),
                this.dropdown_value(type_filter_values, type_filter_dropdown),
                path_filter_entry.get_text())
        }.bindenv(this)

        search_entry.connect("changed", refresh_transactions)
        start_entry.connect("changed", refresh_transactions)
        end_entry.connect("changed", refresh_transactions)
        account_filter_dropdown.connect("notify::selected", function(_) { refresh_transactions() })
        type_filter_dropdown.connect("notify::selected", function(_) { refresh_transactions() })
        path_filter_entry.connect("changed", refresh_transactions)
        refresh_transactions()

        local transaction_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local transaction_button = this.ui.plain_button("Add Transaction", function() {
            if (this.document.accounts.len() == 0) {
                this.set_status("Add an account before recording transactions.")
                return
            }
            local path = this.ensure_envelope_path("expense")
            local txn = Models.Transaction(
                this.make_id("txn"),
                this.first_account_id(),
                this.document.start_date,
                "expense",
                path.folder_id,
                path.envelope_id,
                "New transaction",
                0.0)
            this.show_transaction_editor(txn, refresh_transactions, true)
        }.bindenv(this))
        transaction_button.set_sensitive(this.document.accounts.len() > 0)
        transaction_actions.append(transaction_button)

        transaction_actions.append(this.ui.plain_button("Import CSV/QIF", function() {
            this.show_import_options(refresh_transactions)
        }.bindenv(this)))

        local qif_path = Gtk.Entry.new()
        qif_path.set_hexpand(true)
        qif_path.set_placeholder_text("Export QIF path")
        transaction_actions.append(qif_path)
        transaction_actions.append(this.ui.plain_button("Export QIF", function() {
            this.export_qif(qif_path.get_text())
        }.bindenv(this)))
        root.append(transaction_actions)

        this.show_window("Transactions", root, 1180, 760)
    }

    function add_account_editor_row(list, account) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 10)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local name_entry = Gtk.Entry.new()
        name_entry.set_hexpand(true)
        name_entry.set_placeholder_text("Account name")
        name_entry.set_text(account.name)
        name_entry.connect("changed", function() {
            account.name = name_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(name_entry)

        local number_entry = Gtk.Entry.new()
        number_entry.set_placeholder_text("Number")
        number_entry.set_text(account.number)
        number_entry.connect("changed", function() {
            account.number = number_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(number_entry)

        local balance_entry = Gtk.Entry.new()
        balance_entry.set_placeholder_text("Balance")
        balance_entry.set_text(this.amount_text(account.balance))
        balance_entry.connect("changed", function() {
            local value = this.parse_amount(balance_entry.get_text())
            if (value == null) return
            account.balance = value
            this.persist_document()
        }.bindenv(this))
        box.append(balance_entry)

        local current_balance = Gtk.Label.new(this.money(this.document.account_balance(account)) + " current")
        current_balance.set_xalign(1.0)
        box.append(current_balance)

        local description_entry = Gtk.Entry.new()
        description_entry.set_hexpand(true)
        description_entry.set_placeholder_text("Description")
        description_entry.set_text(account.description)
        description_entry.connect("changed", function() {
            account.description = description_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(description_entry)

        box.append(this.ui.plain_button("Delete", function() {
            this.remove_array_item_by_id(this.document.accounts, account.id)
            for (local i = this.document.transactions.len() - 1; i >= 0; i = i - 1) {
                if (this.document.transactions[i].affects_account(account.id))
                    this.document.transactions.remove(i)
            }
            list.remove(row)
            this.persist_document("Deleted account and related transactions.")
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
        return name_entry
    }

    function transaction_matches_filter(txn, search, start_date, end_date,
                                        account_filter = "", type_filter = "",
                                        path_filter = "") {
        if (search != null && search.len() > 0) {
            local needle = search.tolower()
            local haystack = txn.description + " " +
                this.transaction_account_label(txn) + " " +
                this.transaction_envelope_label(txn)
            if (haystack.tolower().find(needle) == null) return false
        }
        if (start_date != null && start_date.len() > 0 && txn.date < start_date) return false
        if (end_date != null && end_date.len() > 0 && txn.date > end_date) return false
        if (account_filter != null && account_filter.len() > 0 && !txn.affects_account(account_filter)) return false
        if (type_filter != null && type_filter.len() > 0 && txn.type != type_filter) return false
        if (path_filter != null && path_filter.len() > 0) {
            local path = (txn.folder_id + "/" + txn.envelope_id + " " + this.transaction_envelope_label(txn)).tolower()
            if (path.find(path_filter.tolower()) == null) return false
        }
        return true
    }

    function populate_transaction_rows(list, search = "", start_date = "", end_date = "",
                                       account_filter = "", type_filter = "",
                                       path_filter = "") {
        this.clear_listbox(list)
        this.add_transaction_header_row(list)
        local count = 0
        foreach (txn in this.document.transactions) {
            if (this.transaction_matches_filter(txn, search, start_date, end_date,
                    account_filter, type_filter, path_filter)) {
                count = count + 1
                this.add_transaction_row(list, txn, function() {
                    this.populate_transaction_rows(list, search, start_date, end_date,
                        account_filter, type_filter, path_filter)
                }.bindenv(this))
            }
        }
        if (count == 0)
            this.add_empty_list_row(list, "No transactions match these filters.")
    }

    function add_transaction_header_row(list) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 12)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local date = this.ui.label("Date", "dim-label")
        date.set_size_request(96, -1)
        box.append(date)
        local details = this.ui.label("Transaction", "dim-label")
        details.set_hexpand(true)
        box.append(details)
        local amount = Gtk.Label.new("Amount")
        amount.set_xalign(1.0)
        amount.set_size_request(110, -1)
        amount.add_css_class("dim-label")
        box.append(amount)
        local actions = this.ui.label("Actions", "dim-label")
        actions.set_size_request(180, -1)
        box.append(actions)

        row.set_child(box)
        list.append(row)
    }

    function add_transaction_row(list, txn, refresh = null) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 12)
        box.set_margin_top(10)
        box.set_margin_bottom(10)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local date_label = Gtk.Label.new(txn.date)
        date_label.set_xalign(0.0)
        date_label.set_size_request(96, -1)
        box.append(date_label)

        local details = Gtk.Box.new(Gtk.Orientation.vertical, 3)
        details.set_hexpand(true)
        local description = this.ui.label(txn.description.len() > 0 ? txn.description : "Untitled transaction")
        description.set_wrap(true)
        details.append(description)
        local meta = this.ui.label(
            this.transaction_account_label(txn) + " | " +
            this.type_label(txn.type) + " | " +
            this.transaction_envelope_label(txn),
            "dim-label")
        meta.set_wrap(true)
        details.append(meta)
        box.append(details)

        local amount = Gtk.Label.new(this.transaction_amount_label(txn))
        amount.set_xalign(1.0)
        amount.set_size_request(110, -1)
        box.append(amount)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 6)
        actions.set_size_request(180, -1)
        actions.append(this.ui.plain_button("Edit", function() {
            this.show_transaction_editor(txn, refresh)
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Splits", function() {
            this.show_transaction_splits(txn)
        }.bindenv(this)))

        actions.append(this.ui.plain_button("Delete", function() {
            this.remove_array_item_by_id(this.document.transactions, txn.id)
            list.remove(row)
            this.persist_document("Deleted transaction.")
            if (refresh != null) refresh()
        }.bindenv(this)))
        box.append(actions)

        row.set_child(box)
        list.append(row)
    }

    function show_transaction_editor(txn, refresh = null, add_on_save = false) {
        local root = this.module_window(
            add_on_save ? "Add Transaction" : "Edit Transaction",
            "Transaction details and account assignment.",
            "report.png")

        local date_entry = Gtk.Entry.new()
        date_entry.set_text(txn.date)
        root.append(this.labeled_control("Date", date_entry))

        local account_opts = this.account_options(false, true)
        local account_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_opts.labels), null)
        account_dropdown.set_selected(this.index_for_value(account_opts.ids, txn.account_id, 0))
        root.append(this.labeled_control("Account", account_dropdown))

        local type_values = ["income", "expense", "transfer"]
        local type_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Income", "Expense", "Transfer"]), null)
        type_dropdown.set_selected(this.index_for_value(type_values, txn.type, 1))
        root.append(this.labeled_control("Type", type_dropdown))

        local selected_type = this.dropdown_value(type_values, type_dropdown, txn.type)
        local envelope_opts = this.envelope_options(selected_type)
        local envelope_dropdown = Gtk.DropDown.new(Gtk.StringList.new(envelope_opts.labels), null)
        envelope_dropdown.set_selected(this.index_for_value(
            envelope_opts.paths,
            this.envelope_path(txn.folder_id, txn.envelope_id),
            0))
        envelope_dropdown.set_sensitive(selected_type != "transfer")
        root.append(this.labeled_control("Envelope", envelope_dropdown))

        local refresh_envelope_dropdown = function(preferred_path = null) {
            local current_type = this.dropdown_value(type_values, type_dropdown, txn.type)
            envelope_opts = this.envelope_options(current_type)
            envelope_dropdown.set_model(Gtk.StringList.new(envelope_opts.labels))
            local wanted = preferred_path != null ? preferred_path :
                this.envelope_path(txn.folder_id, txn.envelope_id)
            envelope_dropdown.set_selected(this.index_for_value(envelope_opts.paths, wanted, 0))
            envelope_dropdown.set_sensitive(current_type != "transfer")
        }.bindenv(this)

        type_dropdown.connect("notify::selected", function(_) {
            refresh_envelope_dropdown()
        })

        local description_entry = Gtk.Entry.new()
        description_entry.set_text(txn.description)
        root.append(this.labeled_control("Description", description_entry))

        local amount_entry = Gtk.Entry.new()
        amount_entry.set_text(this.amount_text(txn.amount))
        root.append(this.labeled_control("Amount", amount_entry))

        local transfer_opts = this.account_options(false, true)
        local transfer_dropdown = Gtk.DropDown.new(Gtk.StringList.new(transfer_opts.labels), null)
        transfer_dropdown.set_selected(this.index_for_value(transfer_opts.ids, txn.transfer_account_id, 0))
        root.append(this.labeled_control("Transfer to", transfer_dropdown))

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Auto-envelope", function() {
            local selected_type = this.dropdown_value(type_values, type_dropdown, txn.type)
            local rule = this.match_import_rule(description_entry.get_text(), selected_type)
            if (rule == null) {
                this.set_status("No import rule matched " + description_entry.get_text())
                return
            }
            local path = this.import_rule_envelope_path(rule, selected_type)
            type_dropdown.set_selected(this.index_for_value(type_values, path.type, 1))
            refresh_envelope_dropdown(path.folder_id + "/" + path.envelope_id)
            if (path.created) this.persist_document()
            this.set_status("Matched " + description_entry.get_text() + " to " + path.name + ".")
        }.bindenv(this)))

        local win = null
        actions.append(this.ui.plain_button("Save", function() {
            local amount = this.parse_amount(amount_entry.get_text())
            if (amount == null) {
                this.set_status("Enter a valid transaction amount.")
                return
            }

            txn.date = date_entry.get_text()
            txn.account_id = this.dropdown_value(account_opts.ids, account_dropdown)
            txn.type = this.dropdown_value(type_values, type_dropdown, txn.type)
            txn.description = description_entry.get_text()
            txn.amount = amount
            txn.transfer_account_id = this.dropdown_value(transfer_opts.ids, transfer_dropdown)

            if (txn.type == "transfer") {
                txn.folder_id = ""
                txn.envelope_id = ""
            } else {
                local path_text = this.dropdown_value(envelope_opts.paths, envelope_dropdown, "")
                local slash = path_text.find("/")
                if (slash == null) {
                    this.set_status("Choose an envelope for this transaction.")
                    return
                }
                local folder_id = path_text.slice(0, slash)
                local envelope_id = path_text.slice(slash + 1)
                local envelope = this.document.find_envelope(txn.type, folder_id, envelope_id)
                if (envelope == null) {
                    this.set_status("Envelope path is not real for " + this.type_label(txn.type) + ": " + path_text)
                    return
                }
                txn.folder_id = folder_id
                txn.envelope_id = envelope_id
            }

            if (add_on_save) this.document.add_transaction(txn)
            this.persist_document(add_on_save ? "Added transaction." : "Updated transaction.")
            if (refresh != null) refresh()
            if (win != null) win.close()
        }.bindenv(this)))
        root.append(actions)

        win = this.show_window(add_on_save ? "Add Transaction" : "Edit Transaction", root, 680, 480)
    }

    function show_transaction_splits(txn) {
        local root = this.module_window(
            "Transaction Splits",
            "Split one transaction across multiple budget envelopes.",
            "budget.png")

        local summary = Gtk.Label.new("")
        summary.set_xalign(0.0)
        root.append(summary)

        local list_data = this.ui.scrolled_list()
        root.append(list_data.scroll)

        local refresh = function() {
            summary.set_text(
                "Transaction " + this.money(txn.amount) +
                " / split total " + this.money(txn.split_total()))
            this.refresh_title()
        }.bindenv(this)

        foreach (split in txn.splits)
            this.add_split_editor_row(list_data.list, txn, split, refresh)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Add Split", function() {
            local path = this.ensure_envelope_path(txn.type == "income" ? "income" : "expense")
            local split = Models.TransactionSplit(path.folder_id, path.envelope_id, txn.description, 0.0)
            txn.splits.push(split)
            this.add_split_editor_row(list_data.list, txn, split, refresh)
            this.persist_document("Added transaction split.")
            refresh()
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Use Transaction Envelope", function() {
            if (txn.splits.len() == 0) {
                local split = Models.TransactionSplit(txn.folder_id, txn.envelope_id, txn.description, txn.amount)
                txn.splits.push(split)
                this.add_split_editor_row(list_data.list, txn, split, refresh)
                this.persist_document("Created split from transaction envelope.")
                refresh()
            }
        }.bindenv(this)))
        root.append(actions)

        refresh()
        this.show_window("Transaction Splits", root, 760, 420)
    }

    function add_split_editor_row(list, txn, split, refresh = null) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local path_entry = Gtk.Entry.new()
        path_entry.set_hexpand(true)
        path_entry.set_placeholder_text("folder_id/envelope_id")
        path_entry.set_text(split.folder_id + "/" + split.envelope_id)
        path_entry.connect("changed", function() {
            local text = path_entry.get_text()
            local slash = text.find("/")
            if (slash != null) {
                local folder_id = text.slice(0, slash)
                local envelope_id = text.slice(slash + 1)
                if (this.document.find_envelope(txn.type, folder_id, envelope_id) == null) {
                    this.set_status("Split envelope path is not real for " + this.type_label(txn.type) + ": " + text)
                    return
                }
                split.folder_id = folder_id
                split.envelope_id = envelope_id
                this.persist_document()
                if (refresh != null) refresh()
            }
        }.bindenv(this))
        box.append(path_entry)

        local desc_entry = Gtk.Entry.new()
        desc_entry.set_hexpand(true)
        desc_entry.set_placeholder_text("Description")
        desc_entry.set_text(split.description)
        desc_entry.connect("changed", function() {
            split.description = desc_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(desc_entry)

        local amount_entry = Gtk.Entry.new()
        amount_entry.set_placeholder_text("Amount")
        amount_entry.set_text(this.amount_text(split.amount))
        amount_entry.connect("changed", function() {
            local value = this.parse_amount(amount_entry.get_text())
            if (value == null) return
            split.amount = value
            this.persist_document()
            if (refresh != null) refresh()
        }.bindenv(this))
        box.append(amount_entry)

        box.append(this.ui.plain_button("Delete", function() {
            for (local i = txn.splits.len() - 1; i >= 0; i = i - 1) {
                if (txn.splits[i] == split) txn.splits.remove(i)
            }
            list.remove(row)
            this.persist_document("Deleted transaction split.")
            if (refresh != null) refresh()
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
    }

    function import_qif(path, account_id = null) {
        if (path == null || path.len() == 0) {
            this.set_status("Enter a QIF path before importing.")
            return 0
        }

        local file = Gio.File.new_for_path(path)
        if (!file.query_exists(null)) {
            this.set_status("QIF file not found: " + path)
            return 0
        }

        local data = file.load_contents(null)[0]
        local current = { date = this.document.start_date, description = "", amount = 0.0 }
        local imported = 0
        foreach (line in this.scan_lines(data)) {
            if (line.len() == 0) continue
            local tag = line.slice(0, 1)
            local value = line.len() > 1 ? line.slice(1) : ""

            if (tag == "D") current.date = value
            else if (tag == "P" || tag == "M") current.description = value
            else if (tag == "T") current.amount = this.parse_amount(value) == null ? 0.0 : this.parse_amount(value)
            else if (tag == "^") {
                local txn = this.imported_transaction(current.date, current.description, current.amount, account_id)
                if (txn != null) {
                    this.document.add_transaction(txn)
                    imported = imported + 1
                }
                current = { date = this.document.start_date, description = "", amount = 0.0 }
            }
        }

        this.persist_document("Imported " + imported + " QIF transaction(s).")
        return imported
    }

    function csv_signed_amount(row, amount_col, debit_col, credit_col) {
        local amount_text = this.csv_field(row, amount_col)
        if (amount_text.len() > 0) {
            local parsed = this.parse_import_amount(amount_text)
            if (parsed != null) return parsed
        }

        local debit_text = this.csv_field(row, debit_col)
        local credit_text = this.csv_field(row, credit_col)
        local debit = debit_text.len() > 0 ? this.parse_import_amount(debit_text) : null
        local credit = credit_text.len() > 0 ? this.parse_import_amount(credit_text) : null
        if (credit != null && credit != 0.0) return credit < 0.0 ? (credit * -1.0) : credit
        if (debit != null && debit != 0.0) return debit < 0.0 ? debit : (debit * -1.0)
        return null
    }

    function import_csv(path, account_id = null, date_col = 0, description_col = 1,
                        amount_col = 2, memo_col = -1, debit_col = -1,
                        credit_col = -1, skip_header = true) {
        if (path == null || path.len() == 0) {
            this.set_status("Enter a CSV path before importing.")
            return 0
        }

        local file = Gio.File.new_for_path(path)
        if (!file.query_exists(null)) {
            this.set_status("CSV file not found: " + path)
            return 0
        }

        local data = file.load_contents(null)[0]
        local imported = 0
        local row_number = 0
        foreach (line in this.scan_lines(data)) {
            if (this.trim(line).len() == 0) continue
            row_number = row_number + 1
            if (skip_header && row_number == 1) continue

            local row = this.parse_csv_line(line)
            local date = this.csv_field(row, date_col)
            local description = this.csv_field(row, description_col)
            local memo = this.csv_field(row, memo_col)
            if (memo.len() > 0) description = description + " " + memo
            local signed_amount = this.csv_signed_amount(row, amount_col, debit_col, credit_col)
            local txn = this.imported_transaction(date, description, signed_amount, account_id)
            if (txn == null) continue

            this.document.add_transaction(txn)
            imported = imported + 1
        }

        this.persist_document("Imported " + imported + " CSV transaction(s).")
        return imported
    }

    function export_qif(path) {
        if (path == null || path.len() == 0) {
            this.set_status("Enter a QIF path before exporting.")
            return
        }

        local out = "!Type:Bank\n"
        foreach (txn in this.document.transactions) {
            local amount = txn.type == "expense" ? (txn.amount * -1.0) : txn.amount
            out += "D" + txn.date + "\n"
            out += "T" + format("%.2f", amount) + "\n"
            out += "P" + txn.description + "\n"
            out += "^\n"
        }
        GLib.file_set_contents(path, out, -1)
        this.set_status("Exported " + this.document.transactions.len() + " transaction(s) to " + path)
    }

    function string_ends_with(text, suffix) {
        if (text == null || suffix == null) return false
        if (text.len() < suffix.len()) return false
        return text.slice(text.len() - suffix.len()) == suffix
    }

    function import_file_filter(name, patterns) {
        local filter = Gtk.FileFilter.new()
        filter.set_name(name)
        foreach (pattern in patterns)
            filter.add_pattern(pattern)
        return filter
    }

    function choose_import_file(path_entry, format_dropdown, on_chosen = null) {
        local chooser = Gtk.FileChooserNative.new(
            "Choose CSV or QIF File",
            this.window,
            Gtk.FileChooserAction.open,
            "Choose",
            "Cancel")

        local combined_filter = this.import_file_filter(
            "CSV and QIF files",
            ["*.csv", "*.CSV", "*.qif", "*.QIF"])
        local csv_filter = this.import_file_filter("CSV files", ["*.csv", "*.CSV"])
        local qif_filter = this.import_file_filter("QIF files", ["*.qif", "*.QIF"])

        chooser.add_filter(combined_filter)
        chooser.add_filter(csv_filter)
        chooser.add_filter(qif_filter)
        chooser.set_filter(format_dropdown.get_selected() == 1 ? qif_filter : csv_filter)

        this.active_file_chooser = chooser
        chooser.connect("response", function(response_id) {
            if (response_id == Gtk.ResponseType.accept || response_id == Gtk.ResponseType.ok) {
                local file = chooser.get_file()
                if (file != null) {
                    local path = file.get_path()
                    if (path != null && path.len() > 0) {
                        path_entry.set_text(path)
                        local lower = path.tolower()
                        if (this.string_ends_with(lower, ".qif")) format_dropdown.set_selected(1)
                        else if (this.string_ends_with(lower, ".csv")) format_dropdown.set_selected(0)
                        if (on_chosen != null) on_chosen(path)
                    }
                }
            }
            chooser.destroy()
            this.active_file_chooser = null
        }.bindenv(this))
        chooser.show()
    }

    function show_import_options(refresh_transactions = null) {
        local root = this.module_window(
            "Import Transactions",
            "Import CSV or QIF transactions and assign envelopes with regex match rules.",
            "report.png")

        local run_import = null
        local source_box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local path_entry = Gtk.Entry.new()
        path_entry.set_hexpand(true)
        path_entry.set_placeholder_text("CSV or QIF path")
        local format_list = Gtk.StringList.new(["CSV", "QIF"])
        local format_dropdown = Gtk.DropDown.new(format_list, null)
        local account_opts = this.account_options(false, true)
        local account_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_opts.labels), null)
        account_dropdown.set_selected(this.index_for_value(account_opts.ids, this.first_account_id(), 0))
        source_box.append(path_entry)
        source_box.append(this.ui.plain_button("Choose & Import", function() {
            this.choose_import_file(path_entry, format_dropdown, function(path) {
                if (run_import != null) run_import()
            })
        }.bindenv(this)))
        source_box.append(format_dropdown)
        source_box.append(account_dropdown)
        root.append(source_box)

        local csv_box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local date_col = Gtk.Entry.new()
        date_col.set_placeholder_text("Date col")
        date_col.set_text("0")
        local description_col = Gtk.Entry.new()
        description_col.set_placeholder_text("Description col")
        description_col.set_text("1")
        local amount_col = Gtk.Entry.new()
        amount_col.set_placeholder_text("Amount col")
        amount_col.set_text("2")
        local memo_col = Gtk.Entry.new()
        memo_col.set_placeholder_text("Memo col")
        local debit_col = Gtk.Entry.new()
        debit_col.set_placeholder_text("Debit col")
        local credit_col = Gtk.Entry.new()
        credit_col.set_placeholder_text("Credit col")
        local skip_header = Gtk.CheckButton.new_with_label("Header row")
        skip_header.set_active(true)
        csv_box.append(date_col)
        csv_box.append(description_col)
        csv_box.append(amount_col)
        csv_box.append(memo_col)
        csv_box.append(debit_col)
        csv_box.append(credit_col)
        csv_box.append(skip_header)
        root.append(csv_box)

        local import_status = this.ui.label("", "dim-label")

        run_import = function() {
            local path = path_entry.get_text()
            if (path == null || path.len() == 0) {
                import_status.set_text("Choose a CSV or QIF file before importing.")
                this.set_status("Choose a CSV or QIF file before importing.")
                return
            }

            if (!Gio.File.new_for_path(path).query_exists(null)) {
                import_status.set_text("File not found: " + path)
                this.set_status("File not found: " + path)
                return
            }

            local imported = 0
            if (format_dropdown.get_selected() == 0) {
                imported = this.import_csv(
                    path,
                    this.dropdown_value(account_opts.ids, account_dropdown),
                    this.parse_column_index(date_col.get_text(), 0),
                    this.parse_column_index(description_col.get_text(), 1),
                    this.parse_column_index(amount_col.get_text(), 2),
                    this.parse_column_index(memo_col.get_text(), -1),
                    this.parse_column_index(debit_col.get_text(), -1),
                    this.parse_column_index(credit_col.get_text(), -1),
                    skip_header.get_active())
            } else {
                imported = this.import_qif(path, this.dropdown_value(account_opts.ids, account_dropdown))
            }
            if (imported == 0)
                import_status.set_text("No transactions imported. Check the file format and column settings.")
            else
                import_status.set_text("Imported " + imported + " transaction(s) from " + path)
            if (refresh_transactions != null) refresh_transactions()
        }.bindenv(this)

        local import_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        import_actions.append(this.ui.plain_button("Import", function() {
            run_import()
        }.bindenv(this)))
        import_actions.append(this.ui.plain_button("Export QIF", function() {
            this.export_qif(path_entry.get_text())
        }.bindenv(this)))
        root.append(import_actions)
        root.append(import_status)

        root.append(this.ui.label("Envelope Match Rules", "title-3"))
        local rules_data = this.ui.scrolled_list()
        this.populate_import_rule_rows(rules_data.list)
        root.append(rules_data.scroll)

        local rule_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        rule_actions.append(this.ui.plain_button("Add Rule", function() {
            local path = this.ensure_envelope_path("expense")
            local rule = Models.ImportRule(
                this.make_id("rule"),
                "New Rule",
                "(?i)merchant",
                path.type,
                path.folder_id,
                path.envelope_id,
                100)
            this.document.add_import_rule(rule)
            this.add_import_rule_editor_row(rules_data.list, rule)
            this.persist_document("Added import match rule.")
        }.bindenv(this)))
        rule_actions.append(this.ui.plain_button("Reset Defaults", function() {
            this.document.import_rules = []
            Models.ensure_default_import_rules(this.document)
            this.populate_import_rule_rows(rules_data.list)
            this.persist_document("Restored default import match rules.")
        }.bindenv(this)))
        root.append(rule_actions)

        this.show_window("Import Transactions", root, 1040, 680)
    }

    function populate_import_rule_rows(list) {
        this.clear_listbox(list)
        foreach (rule in this.document.import_rules)
            this.add_import_rule_editor_row(list, rule)
    }

    function add_import_rule_editor_row(list, rule) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local enabled = Gtk.CheckButton.new_with_label("On")
        enabled.set_active(rule.enabled)
        enabled.connect("toggled", function() {
            rule.enabled = enabled.get_active()
            this.persist_document()
        }.bindenv(this))
        box.append(enabled)

        local name_entry = Gtk.Entry.new()
        name_entry.set_placeholder_text("Name")
        name_entry.set_text(rule.name)
        name_entry.connect("changed", function() {
            rule.name = name_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(name_entry)

        local pattern_entry = Gtk.Entry.new()
        pattern_entry.set_hexpand(true)
        pattern_entry.set_placeholder_text("Regex pattern")
        pattern_entry.set_text(rule.pattern)
        pattern_entry.connect("changed", function() {
            rule.pattern = pattern_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(pattern_entry)

        local type_entry = Gtk.Entry.new()
        type_entry.set_placeholder_text("Type")
        type_entry.set_text(rule.type)
        type_entry.connect("changed", function() {
            rule.type = type_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(type_entry)

        local path_entry = Gtk.Entry.new()
        path_entry.set_hexpand(true)
        path_entry.set_placeholder_text("folder_id/envelope_id")
        path_entry.set_text(rule.folder_id + "/" + rule.envelope_id)
        path_entry.connect("changed", function() {
            local text = path_entry.get_text()
            local slash = text.find("/")
            if (slash != null) {
                local folder_id = text.slice(0, slash)
                local envelope_id = text.slice(slash + 1)
                if (this.document.find_envelope(type_entry.get_text(), folder_id, envelope_id) == null) {
                    this.set_status("Rule target is not a real envelope: " + text)
                    return
                }
                rule.folder_id = folder_id
                rule.envelope_id = envelope_id
                this.persist_document()
            }
        }.bindenv(this))
        box.append(path_entry)

        local priority_entry = Gtk.Entry.new()
        priority_entry.set_placeholder_text("Priority")
        priority_entry.set_text("" + rule.priority)
        priority_entry.connect("changed", function() {
            rule.priority = this.parse_column_index(priority_entry.get_text(), rule.priority)
            this.persist_document()
        }.bindenv(this))
        box.append(priority_entry)

        local test_entry = Gtk.Entry.new()
        test_entry.set_placeholder_text("Test text")
        box.append(test_entry)
        box.append(this.ui.plain_button("Test", function() {
            local matched = this.regex_matches(pattern_entry.get_text(), test_entry.get_text())
            this.set_status(rule.name + ": " + (matched ? "matched" : "no match"))
        }.bindenv(this)))

        box.append(this.ui.plain_button("Delete", function() {
            this.remove_array_item_by_id(this.document.import_rules, rule.id)
            list.remove(row)
            this.persist_document("Deleted import match rule.")
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
    }

    function show_budget() {
        local root = this.module_window(
            "Edit Budget",
            "Envelope budgets for the selected period. Income and expense rows are backed by the envelope catalog.",
            "budget.png")

        local summary = Gtk.Box.new(Gtk.Orientation.horizontal, 16)
        local summary_labels = {
            income = Gtk.Label.new(""),
            expenses = Gtk.Label.new(""),
            reserve = Gtk.Label.new(""),
            unallocated = Gtk.Label.new("")
        }
        foreach (label in [summary_labels.income, summary_labels.expenses, summary_labels.reserve, summary_labels.unallocated]) {
            label.set_xalign(0.0)
            summary.append(label)
        }
        root.append(summary)

        local balance_area = Gtk.DrawingArea.new()
        balance_area.set_size_request(680, 46)
        balance_area.set_draw_func(function(widget, cr, width, height) {
            this.draw_balance_indicator(cr, width, height)
        }.bindenv(this), null, function(_) {})
        root.append(balance_area)

        local refresh_budget = function() {
            this.refresh_budget_summary(summary_labels, balance_area)
        }.bindenv(this)

        local list_data = this.ui.scrolled_list()
        foreach (item in this.document.budgets)
            this.add_budget_editor_row(list_data.list, item, refresh_budget)
        root.append(list_data.scroll)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Add Expense", function() {
            local envelope = this.create_envelope_and_budget("expense")
            local name_entry = this.add_budget_editor_row(list_data.list, envelope, refresh_budget)
            name_entry.grab_focus()
            this.persist_document("Added expense budget and stored it in Spinodb.")
            refresh_budget()
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Add Income", function() {
            local envelope = this.create_envelope_and_budget("income")
            local name_entry = this.add_budget_editor_row(list_data.list, envelope, refresh_budget)
            name_entry.grab_focus()
            this.persist_document("Added income budget and stored it in Spinodb.")
            refresh_budget()
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Choose Expense", function() {
            this.show_budget_envelope_chooser("expense", list_data.list, refresh_budget)
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Choose Income", function() {
            this.show_budget_envelope_chooser("income", list_data.list, refresh_budget)
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Clear Budget", function() {
            this.document.budgets = []
            this.clear_listbox(list_data.list)
            this.persist_document("Cleared the current budget.")
            refresh_budget()
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Copy Budget", function() {
            local originals = []
            foreach (item in this.document.budgets) originals.push(item)
            foreach (item in originals) {
                local copied = Models.BudgetEnvelope(
                    this.make_id("budget-copy"),
                    item.name,
                    item.budgeted,
                    item.spent,
                    item.type,
                    item.folder_id,
                    item.envelope_id,
                    this.document.current_period())
                this.document.add_budget(copied)
                this.add_budget_editor_row(list_data.list, copied, refresh_budget)
            }
            this.persist_document("Copied the budget rows.")
            refresh_budget()
        }.bindenv(this)))
        root.append(actions)

        refresh_budget()
        this.show_window("Edit Budget", root)
    }

    function add_budget_editor_row(list, envelope, refresh_budget = null) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 10)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local name_entry = Gtk.Entry.new()
        name_entry.set_hexpand(true)
        name_entry.set_placeholder_text("Envelope name")
        name_entry.set_text(this.document.budget_name(envelope))
        name_entry.connect("changed", function() {
            envelope.name = name_entry.get_text()
            local linked = this.document.find_envelope(envelope.type, envelope.folder_id, envelope.envelope_id)
            if (linked != null) linked.name = envelope.name
            this.persist_document()
            if (refresh_budget != null) refresh_budget()
        }.bindenv(this))
        box.append(name_entry)

        if (envelope.type != "income" && envelope.type != "expense")
            envelope.type = "expense"
        local resolved_path = this.ensure_envelope_path(
            envelope.type,
            envelope.folder_id,
            envelope.envelope_id,
            envelope.name)
        envelope.type = resolved_path.type
        envelope.folder_id = resolved_path.folder_id
        envelope.envelope_id = resolved_path.envelope_id
        if (resolved_path.created) this.persist_document()

        local type_values = ["expense", "income"]
        local type_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Expense", "Income"]), null)
        type_dropdown.set_selected(this.index_for_value(type_values, envelope.type, 0))
        box.append(type_dropdown)

        local envelope_opts = this.envelope_options(envelope.type)
        local envelope_dropdown = Gtk.DropDown.new(Gtk.StringList.new(envelope_opts.labels), null)
        envelope_dropdown.set_hexpand(true)
        envelope_dropdown.set_selected(this.index_for_value(
            envelope_opts.paths,
            this.envelope_path(envelope.folder_id, envelope.envelope_id),
            0))
        box.append(envelope_dropdown)

        local apply_envelope_selection = function() {
            local selected_type = this.dropdown_value(type_values, type_dropdown, envelope.type)
            local path_text = this.dropdown_value(envelope_opts.paths, envelope_dropdown, "")
            local slash = path_text.find("/")
            if (slash == null) return

            local folder_id = path_text.slice(0, slash)
            local envelope_id = path_text.slice(slash + 1)
            local linked = this.document.find_envelope(selected_type, folder_id, envelope_id)
            if (linked == null) {
                this.set_status("Budget envelope selection is no longer available: " + path_text)
                return
            }

            envelope.type = selected_type
            envelope.folder_id = folder_id
            envelope.envelope_id = envelope_id
            envelope.name = linked.name
            if (name_entry.get_text() != linked.name) name_entry.set_text(linked.name)
            this.persist_document()
            if (refresh_budget != null) refresh_budget()
        }.bindenv(this)

        local refresh_envelope_dropdown = function(preferred_path = null) {
            local selected_type = this.dropdown_value(type_values, type_dropdown, envelope.type)
            envelope_opts = this.envelope_options(selected_type)
            envelope_dropdown.set_model(Gtk.StringList.new(envelope_opts.labels))
            local wanted = preferred_path != null ? preferred_path :
                this.envelope_path(envelope.folder_id, envelope.envelope_id)
            envelope_dropdown.set_selected(this.index_for_value(envelope_opts.paths, wanted, 0))
        }.bindenv(this)

        type_dropdown.connect("notify::selected", function(_) {
            refresh_envelope_dropdown()
            apply_envelope_selection()
        })
        envelope_dropdown.connect("notify::selected", function(_) {
            apply_envelope_selection()
        })

        local allocation_entry = Gtk.Entry.new()
        allocation_entry.set_placeholder_text("Allocated")
        allocation_entry.set_text(this.amount_text(envelope.budgeted))
        allocation_entry.connect("changed", function() {
            local value = this.parse_amount(allocation_entry.get_text())
            if (value == null) return
            envelope.budgeted = value
            this.persist_document()
            if (refresh_budget != null) refresh_budget()
        }.bindenv(this))
        box.append(allocation_entry)

        local spent_label = Gtk.Label.new(this.money(envelope.spent) + " spent")
        spent_label.set_xalign(1.0)
        box.append(spent_label)

        box.append(this.ui.plain_button("Remove", function() {
            this.remove_array_item_by_id(this.document.budgets, envelope.id)
            list.remove(row)
            this.persist_document("Removed budget row.")
            if (refresh_budget != null) refresh_budget()
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
        return name_entry
    }

    function show_budget_envelope_chooser(type, budget_list, refresh_budget = null) {
        local root = this.module_window(
            type == "income" ? "Choose Income Envelope" : "Choose Expense Envelope",
            "Add an existing envelope to the current budget period.",
            "envelope.png")

        local list_data = this.ui.scrolled_list()
        local chooser_win = null

        foreach (folder in this.document.folders_for_type(type)) {
            this.ui.add_row(list_data.list, folder.name, folder.hidden ? "hidden" : null)
            foreach (envelope in folder.envelopes) {
                if (folder.hidden || envelope.hidden) continue
                local chosen_folder = folder
                local chosen_envelope = envelope

                local row = Gtk.ListBoxRow.new()
                local box = Gtk.Box.new(Gtk.Orientation.horizontal, 10)
                box.set_margin_top(6)
                box.set_margin_bottom(6)
                box.set_margin_start(28)
                box.set_margin_end(10)

                local name = this.ui.label(envelope.name)
                name.set_hexpand(true)
                box.append(name)
                box.append(this.ui.plain_button("Use", function() {
                    local budget = this.create_budget_for_envelope(type, chosen_folder, chosen_envelope)
                    this.add_budget_editor_row(budget_list, budget, refresh_budget)
                    this.persist_document("Added existing envelope to budget.")
                    if (refresh_budget != null) refresh_budget()
                    if (chooser_win != null) chooser_win.close()
                }.bindenv(this)))

                row.set_child(box)
                list_data.list.append(row)
            }
        }

        root.append(list_data.scroll)
        chooser_win = this.show_window(type == "income" ? "Choose Income Envelope" : "Choose Expense Envelope", root, 680, 440)
    }

    function draw_balance_indicator(cr, width, height) {
        local income = this.document.total_budgeted("income")
        local expenses = this.document.total_budgeted("expense")
        local reserve = this.document.reserve_enabled ? this.document.reserve_amount : 0.0
        local unallocated = this.document.unallocated_amount()
        local total = income
        if (total < expenses + reserve) total = expenses + reserve
        if (total <= 0.0) total = 1.0

        cr.set_source_rgba(0.15, 0.16, 0.16, 0.14)
        cr.rectangle(0, 10, width, 22)
        cr.fill()

        local x = 0.0
        local expense_width = width * (expenses / total)
        cr.set_source_rgba(0.74, 0.16, 0.15, 0.78)
        cr.rectangle(x, 10, expense_width, 22)
        cr.fill()
        x = x + expense_width

        local reserve_width = width * (reserve / total)
        cr.set_source_rgba(0.76, 0.45, 0.12, 0.78)
        cr.rectangle(x, 10, reserve_width, 22)
        cr.fill()

        if (unallocated >= 0.0) cr.set_source_rgba(0.16, 0.50, 0.38, 0.82)
        else cr.set_source_rgba(0.55, 0.08, 0.08, 0.88)
        local marker_x = width * ((income - (unallocated < 0.0 ? 0.0 : unallocated)) / total)
        if (marker_x < 0.0) marker_x = 0.0
        if (marker_x > width - 4) marker_x = width - 4
        cr.rectangle(marker_x, 4, 4, 34)
        cr.fill()
    }

    function show_budget_report() {
        local root = this.module_window(
            "Budget Report",
            "Report view for " + this.document.current_period() + ".",
            "report.png")

        local summary = Gtk.Box.new(Gtk.Orientation.horizontal, 16)
        summary.append(this.ui.label("Income " + this.money(this.document.total_budgeted("income"))))
        summary.append(this.ui.label("Expenses " + this.money(this.document.total_budgeted("expense"))))
        summary.append(this.ui.label("Spent " + this.money(this.document.total_spent("expense"))))
        summary.append(this.ui.label("Unallocated " + this.money(this.document.unallocated_amount())))
        root.append(summary)

        local notebook = Gtk.Notebook.new()
        local list_data = this.ui.scrolled_list()
        foreach (item in this.document.budgets) {
            local spent = this.document.budget_spent(item)
            this.ui.add_row(list_data.list,
                this.document.budget_name(item),
                this.money(item.budgeted) + " budgeted / " +
                this.money(spent) + " spent / " +
                this.money(item.remaining(spent)) + " remaining")
        }
        notebook.append_page(list_data.scroll, Gtk.Label.new("Table"))

        local area = Gtk.DrawingArea.new()
        area.set_size_request(720, 420)
        area.set_draw_func(function(widget, cr, width, height) {
            this.draw_report_graph(cr, width, height)
        }.bindenv(this), null, function(_) {})
        notebook.append_page(area, Gtk.Label.new("Graph"))

        root.append(notebook)

        this.show_window("Budget Report", root)
    }

    function show_envelopes() {
        local root = this.module_window(
            "Envelopes",
            "Income and expense folders, envelopes, descriptions, and hidden flags.",
            "envelope.png")

        local notebook = Gtk.Notebook.new()
        local income = this.ui.scrolled_list()
        this.populate_envelope_catalog(income.list, "income")
        notebook.append_page(income.scroll, Gtk.Label.new("Income"))

        local expense = this.ui.scrolled_list()
        this.populate_envelope_catalog(expense.list, "expense")
        notebook.append_page(expense.scroll, Gtk.Label.new("Expenses"))

        root.append(notebook)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Add Income Folder", function() {
            local folder = Models.EnvelopeFolder(this.make_id("income-folder"), "New Income Folder", "income")
            this.document.add_income_folder(folder)
            this.add_folder_editor_row(income.list, folder, "income")
            this.persist_document("Added income folder.")
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Add Expense Folder", function() {
            local folder = Models.EnvelopeFolder(this.make_id("expense-folder"), "New Expense Folder", "expense")
            this.document.add_expense_folder(folder)
            this.add_folder_editor_row(expense.list, folder, "expense")
            this.persist_document("Added expense folder.")
        }.bindenv(this)))
        root.append(actions)

        this.show_window("Envelopes", root)
    }

    function populate_envelope_catalog(list, type) {
        this.clear_listbox(list)
        foreach (folder in this.document.folders_for_type(type))
            this.add_folder_editor_row(list, folder, type)
    }

    function add_folder_editor_row(list, folder, type) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local title = this.ui.label("Folder")
        box.append(title)

        local name_entry = Gtk.Entry.new()
        name_entry.set_hexpand(true)
        name_entry.set_placeholder_text("Folder name")
        name_entry.set_text(folder.name)
        name_entry.connect("changed", function() {
            folder.name = name_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(name_entry)

        local hidden = Gtk.CheckButton.new_with_label("Hidden")
        hidden.set_active(folder.hidden)
        hidden.connect("toggled", function() {
            folder.hidden = hidden.get_active()
            this.persist_document()
        }.bindenv(this))
        box.append(hidden)

        box.append(this.ui.plain_button("Add Envelope", function() {
            local envelope = Models.Envelope(this.make_id("env"), "New Envelope", "")
            folder.add_envelope(envelope)
            this.add_envelope_catalog_row(list, folder, envelope, type)
            this.persist_document("Added envelope.")
        }.bindenv(this)))

        box.append(this.ui.plain_button("Delete Folder", function() {
            local folders = this.document.folders_for_type(type)
            this.remove_array_item_by_id(folders, folder.id)
            for (local i = this.document.budgets.len() - 1; i >= 0; i = i - 1) {
                if (this.document.budgets[i].folder_id == folder.id)
                    this.document.budgets.remove(i)
            }
            for (local i = this.document.transactions.len() - 1; i >= 0; i = i - 1) {
                if (this.document.transactions[i].folder_id == folder.id)
                    this.document.transactions.remove(i)
            }
            for (local i = this.document.import_rules.len() - 1; i >= 0; i = i - 1) {
                if (this.document.import_rules[i].type == type &&
                    this.document.import_rules[i].folder_id == folder.id)
                    this.document.import_rules.remove(i)
            }
            this.populate_envelope_catalog(list, type)
            this.persist_document("Deleted folder and related rows.")
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)

        foreach (envelope in folder.envelopes)
            this.add_envelope_catalog_row(list, folder, envelope, type)
    }

    function add_envelope_catalog_row(list, folder, envelope, type) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(36)
        box.set_margin_end(10)

        local name_entry = Gtk.Entry.new()
        name_entry.set_hexpand(true)
        name_entry.set_placeholder_text("Envelope name")
        name_entry.set_text(envelope.name)
        name_entry.connect("changed", function() {
            envelope.name = name_entry.get_text()
            foreach (budget in this.document.budgets) {
                if (budget.type == type && budget.folder_id == folder.id && budget.envelope_id == envelope.id)
                    budget.name = envelope.name
            }
            this.persist_document()
        }.bindenv(this))
        box.append(name_entry)

        local description_entry = Gtk.Entry.new()
        description_entry.set_hexpand(true)
        description_entry.set_placeholder_text("Description")
        description_entry.set_text(envelope.description)
        description_entry.connect("changed", function() {
            envelope.description = description_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        box.append(description_entry)

        local hidden = Gtk.CheckButton.new_with_label("Hidden")
        hidden.set_active(envelope.hidden)
        hidden.connect("toggled", function() {
            envelope.hidden = hidden.get_active()
            this.persist_document()
        }.bindenv(this))
        box.append(hidden)

        box.append(this.ui.plain_button("Delete", function() {
            this.remove_array_item_by_id(folder.envelopes, envelope.id)
            for (local i = this.document.budgets.len() - 1; i >= 0; i = i - 1) {
                local budget = this.document.budgets[i]
                if (budget.type == type && budget.folder_id == folder.id && budget.envelope_id == envelope.id)
                    this.document.budgets.remove(i)
            }
            for (local i = this.document.transactions.len() - 1; i >= 0; i = i - 1) {
                local txn = this.document.transactions[i]
                if (txn.type == type && txn.folder_id == folder.id && txn.envelope_id == envelope.id)
                    this.document.transactions.remove(i)
            }
            for (local i = this.document.import_rules.len() - 1; i >= 0; i = i - 1) {
                local rule = this.document.import_rules[i]
                if (rule.type == type && rule.folder_id == folder.id && rule.envelope_id == envelope.id)
                    this.document.import_rules.remove(i)
            }
            list.remove(row)
            this.persist_document("Deleted envelope and related rows.")
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
    }

    function show_graph(title, icon_name) {
        local root = this.module_window(
            title,
            "Chart window backed by the current Dough document.",
            icon_name)

        local controls = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local mode_entry = Gtk.Entry.new()
        mode_entry.set_hexpand(true)
        mode_entry.set_placeholder_text("Mode")
        mode_entry.set_text(title.find("Pie") == null ? "Income vs Expenses" : "Expense Envelopes")
        local start_entry = Gtk.Entry.new()
        start_entry.set_placeholder_text("Start date")
        start_entry.set_text(this.document.start_date)
        local end_entry = Gtk.Entry.new()
        end_entry.set_placeholder_text("End date")
        end_entry.set_text(this.document.current_period())
        local export_entry = Gtk.Entry.new()
        export_entry.set_hexpand(true)
        export_entry.set_placeholder_text("PNG path")
        export_entry.set_text(this.default_export_path(title.find("Pie") == null ? "dough-line-graph.png" : "dough-pie-chart.png"))
        controls.append(mode_entry)
        controls.append(start_entry)
        controls.append(end_entry)
        controls.append(export_entry)
        controls.append(this.ui.plain_button("Export PNG", function() {
            this.export_graph_png(export_entry.get_text(), title.find("Pie") != null)
        }.bindenv(this)))
        root.append(controls)

        local area = Gtk.DrawingArea.new()
        area.set_size_request(640, 360)
        area.set_draw_func(function(widget, cr, width, height) {
            if (title.find("Pie") == null) this.draw_graph(cr, width, height)
            else this.draw_pie_chart(cr, width, height)
        }.bindenv(this), null, function(_) {})
        mode_entry.connect("changed", function() { area.queue_draw() })
        start_entry.connect("changed", function() { area.queue_draw() })
        end_entry.connect("changed", function() { area.queue_draw() })
        root.append(area)
        this.show_window(title, root)
    }

    function draw_report_graph(cr, width, height) {
        this.draw_graph(cr, width, height)
    }

    function draw_graph(cr, width, height) {
        cr.set_source_rgb(0.96, 0.96, 0.94)
        cr.rectangle(0, 0, width, height)
        cr.fill()
        cr.set_source_rgb(0.16, 0.20, 0.22)
        cr.set_line_width(2)
        cr.move_to(40, height - 40)
        cr.line_to(width - 30, height - 40)
        cr.move_to(40, 30)
        cr.line_to(40, height - 40)
        cr.stroke()

        local x = 70.0
        foreach (item in this.document.budgets) {
            local spent = this.document.budget_spent(item)
            local bar_height = item.budgeted == 0.0 ? 4.0 : (spent / item.budgeted) * 190.0
            if (bar_height > 230.0) bar_height = 230.0
            cr.set_source_rgba(0.15, 0.45, 0.55, 0.78)
            cr.rectangle(x, height - 40 - bar_height, 54, bar_height)
            cr.fill()
            x = x + 78.0
        }
    }

    function draw_pie_chart(cr, width, height) {
        cr.set_source_rgb(0.96, 0.96, 0.94)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        local total = 0.0
        foreach (item in this.document.budgets)
            if (item.type == "expense") total = total + this.document.budget_spent(item)
        if (total <= 0.0) total = this.document.total_budgeted("expense")
        if (total <= 0.0) return

        local colors = [
            [0.15, 0.45, 0.55],
            [0.76, 0.45, 0.12],
            [0.16, 0.50, 0.38],
            [0.74, 0.16, 0.15],
            [0.36, 0.30, 0.58]
        ]
        local cx = width / 2.0
        local cy = height / 2.0
        local radius = (width < height ? width : height) / 3.0
        local angle = -1.57079632679
        local color_index = 0

        foreach (item in this.document.budgets) {
            if (item.type != "expense") continue
            local value = this.document.budget_spent(item)
            if (value <= 0.0) value = item.budgeted
            if (value <= 0.0) continue

            local next_angle = angle + ((value / total) * 6.28318530718)
            local c = colors[color_index % colors.len()]
            cr.set_source_rgba(c[0], c[1], c[2], 0.88)
            cr.move_to(cx, cy)
            cr.arc(cx, cy, radius, angle, next_angle)
            cr.close_path()
            cr.fill()
            angle = next_angle
            color_index = color_index + 1
        }
    }

    function show_options() {
        local root = this.module_window(
            "Options",
            "Dough document metadata and display settings.",
            "interface.png")

        local title_entry = Gtk.Entry.new()
        title_entry.set_text(this.document.title)
        local currency_entry = Gtk.Entry.new()
        currency_entry.set_text(this.document.currency)
        local reserve_entry = Gtk.Entry.new()
        reserve_entry.set_text(this.amount_text(this.document.reserve_amount))
        local reserve_check = Gtk.CheckButton.new_with_label("Reserve enabled")
        reserve_check.set_active(this.document.reserve_enabled)
        local date_format_entry = Gtk.Entry.new()
        date_format_entry.set_text(this.document.date_format)
        local start_date_entry = Gtk.Entry.new()
        start_date_entry.set_text(this.document.start_date)
        local period_length_entry = Gtk.Entry.new()
        period_length_entry.set_text(this.document.period_length)

        root.append(this.ui.label("Budget Title"))
        root.append(title_entry)
        root.append(this.ui.label("Currency Symbol"))
        root.append(currency_entry)
        root.append(reserve_check)
        root.append(this.ui.label("Reserve Amount"))
        root.append(reserve_entry)
        root.append(this.ui.label("Date Format"))
        root.append(date_format_entry)
        root.append(this.ui.label("Start Date"))
        root.append(start_date_entry)
        root.append(this.ui.label("Period Length"))
        root.append(period_length_entry)
        root.append(this.ui.plain_button("Apply", function() {
            this.document.title = title_entry.get_text()
            this.document.currency = currency_entry.get_text()
            this.document.reserve_enabled = reserve_check.get_active()
            local reserve = this.parse_amount(reserve_entry.get_text())
            if (reserve != null) this.document.reserve_amount = reserve
            this.document.date_format = date_format_entry.get_text()
            this.document.start_date = start_date_entry.get_text()
            this.document.period_length = period_length_entry.get_text()
            this.document.regenerate_periods()
            this.persist_document("Options applied and stored in Spinodb.")
        }.bindenv(this)))

        this.show_window("Options", root, 520, 360)
    }

    function show_about() {
        local root = this.ui.padded_box(Gtk.Orientation.vertical, 12, 22)
        root.append(this.ui.picture("logo.png", 320, 180))
        root.append(this.ui.label("Dough", "title-1"))
        local copy = this.ui.label("A free personal finance and budgeting application, ported to GTK4 with SQGI and Spinodb persistence.", "dim-label")
        copy.set_wrap(true)
        root.append(copy)
        this.show_window("About Dough", root, 460, 420)
    }

    function previous_period() {
        if (this.document.period_index > 0) this.document.period_index = this.document.period_index - 1
        this.persist_document("Showing " + this.document.current_period())
    }

    function next_period() {
        if (this.document.period_index < this.document.periods.len() - 1)
            this.document.period_index = this.document.period_index + 1
        this.persist_document("Showing " + this.document.current_period())
    }

    function new_document() {
        this.document = Models.DoughDocument()
        this.document.title = "New Budget"
        this.document.regenerate_periods()
        this.persist_document("Created a new Dough document in Spinodb.")
    }

    function load_sample_document() {
        this.document = Models.sample_document()
        this.persist_document("Loaded sample Dough data.")
    }

    function quit() {
        this.app.quit()
    }

    function run_smoke_test() {
        this.show_accounts()
        this.show_transactions()
        this.show_budget()
        this.show_budget_report()
        this.show_envelopes()
        this.show_graph("Line Graphs", "linegraph.png")
        this.show_graph("Pie Charts", "piechart.png")
        this.show_options()
        this.show_about()

        sqgi.timeout_add(1200, function() {
            this.app.quit()
            return false
        }.bindenv(this))
    }
}

return {
    DoughApplication = DoughApplication
}
