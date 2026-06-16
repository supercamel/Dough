local GLib = import("GLib")
local Gio = import("Gio")
local Gdk = import("Gdk", "4.0")
local Gtk = import("Gtk", "4.0")
local cairo = import("cairo")

local Assets = import("assets.nut")
local Models = import("models.nut")
local Repository = import("repository.nut")
local Helpers = import("ui_helpers.nut")

const DOUGH_APP_ID = "dev.sam.dough"
const DOUGH_APP_NAME = "Dough"
const DOUGH_ICON_NAME = "dev.sam.dough"
const DOUGH_DESKTOP_RELAUNCH_ENV = "DOUGH_DESKTOP_RELAUNCHED"

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
    page_title_label = null
    content_area = null
    app_overlay = null
    overlay_layer = null
    nav_buttons = null
    active_page_id = null
    tutorial_button = null
    tutorial_popover = null
    tutorial_step_index = 0
    tutorial_state = null
    smoke_test = false
    version = "0.1.11"

    constructor(options = null) {
        this.configure_process_identity()
        this.smoke_test = options != null && "smoke" in options ? options.smoke : false
        local db_path = options != null && "db_path" in options ? options.db_path : null
        this.assets = Assets.AssetLocator()
        this.ui = Helpers.WidgetFactory(this.assets)
        this.repository = Repository.SpinodbRepository(db_path)
        this.document = this.repository.load_document()
        this.tutorial_state = this.repository.load_tutorial_state()
        this.repair_transaction_envelope_paths()
        this.nav_buttons = {}
        this.app = Gtk.Application.new(DOUGH_APP_ID, Gio.ApplicationFlags.flags_none)
    }

    function run(argc, argv) {
        if (!this.smoke_test) {
            local desktop_path = this.install_appimage_desktop_entry()
            if (desktop_path != null && this.maybe_relaunch_from_desktop(desktop_path)) return 0
        }

        local self = this
        this.app.connect("activate", function() { self.activate() })
        local status = this.app.run(argc, argv)
        print("Application exited with status " + status + "\n")
        return status
    }

    function activate() {
        if (this.window != null) {
            this.window.present()
            return
        }

        this.configure_app_icon()
        this.install_css()

        this.window = Gtk.ApplicationWindow.new(this.app)
        this.window.set_default_size(1100, 760)
        this.window.set_title(DOUGH_APP_NAME)
        this.apply_window_icon(this.window)

        local header = Gtk.HeaderBar.new()
        this.page_title_label = Gtk.Label.new("Dashboard")
        this.page_title_label.add_css_class("title-3")
        header.set_title_widget(this.page_title_label)
        this.tutorial_button = this.ui.plain_button("Guide", function() { this.start_tutorial() }.bindenv(this),
            "Open the guided setup walkthrough.")
        header.pack_start(this.tutorial_button)
        header.pack_end(this.ui.plain_button("About", function() { this.show_about() }.bindenv(this),
            "Show Dough version and project information."))
        header.pack_end(this.ui.plain_button("Quit", function() { this.quit() }.bindenv(this),
            "Quit Dough."))
        this.window.set_titlebar(header)

        this.app_overlay = Gtk.Overlay.new()
        this.app_overlay.set_child(this.build_shell())
        this.window.set_child(this.app_overlay)
        this.show_dashboard()
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

    function configure_process_identity() {
        GLib.set_prgname(DOUGH_APP_ID)
        GLib.set_application_name(DOUGH_APP_NAME)
        Gtk.Window.set_default_icon_name(DOUGH_ICON_NAME)
    }

    function path_exists(path) {
        return path != null && path != "" && Gio.File.new_for_path(path).query_exists(null)
    }

    function add_icon_search_path(theme, path) {
        if (theme == null || !this.path_exists(path)) return
        theme.add_search_path(path)
    }

    function configure_app_icon() {
        local display = Gdk.Display.get_default()
        if (display != null) {
            local theme = Gtk.IconTheme.get_for_display(display)
            this.add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "assets"]))
            this.add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "share", "icons"]))
            this.add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "usr", "share", "icons"]))

            local resources = GLib.getenv("SQGI_APP_RESOURCES")
            if (resources != null && resources != "") {
                this.add_icon_search_path(theme, GLib.build_filenamev([resources, "assets"]))
            }

            local appdir = GLib.getenv("SQGI_APPDIR")
            if (appdir != null && appdir != "") {
                this.add_icon_search_path(theme, GLib.build_filenamev([appdir, "share", "icons"]))
                this.add_icon_search_path(theme, GLib.build_filenamev([appdir, "usr", "share", "icons"]))
                this.add_icon_search_path(theme, GLib.build_filenamev([appdir, "assets"]))
            }

            local icon_path = this.assets.path(DOUGH_ICON_NAME + ".png")
            if (icon_path == null) icon_path = this.assets.path("icon.png")
            if (icon_path != null) this.add_icon_search_path(theme, GLib.path_get_dirname(icon_path))
        }

        Gtk.Window.set_default_icon_name(DOUGH_ICON_NAME)
    }

    function apply_window_icon(window) {
        if (window == null) return

        try {
            window.set_icon_name(DOUGH_ICON_NAME)
        } catch (e) {
            Gtk.Window.set_default_icon_name(DOUGH_ICON_NAME)
        }
    }

    function desktop_exec_quote(value) {
        local out = "\""
        for (local i = 0; i < value.len(); i++) {
            local ch = value.slice(i, i + 1)
            if (ch == "%") out += "%%"
            else if (ch == "\\" || ch == "\"" || ch == "$" || ch == "`") out += "\\" + ch
            else out += ch
        }
        return out + "\""
    }

    function desktop_launch_exec(appimage) {
        return "env " + DOUGH_DESKTOP_RELAUNCH_ENV + "=1 " + this.desktop_exec_quote(appimage) + " %U"
    }

    function remove_owned_desktop_file(path) {
        if (!this.path_exists(path)) return

        try {
            local text = GLib.file_get_contents(path)
            if (text.find(DOUGH_APP_NAME) == null) return
            if (text.find("X-Dough-AppImage=true") == null &&
                text.find("Icon=dough") == null &&
                text.find("StartupWMClass=dough") == null) return
            GLib.remove(path)
        } catch (e) {
            print("desktop cleanup warning: " + e + "\n")
        }
    }

    function maybe_relaunch_from_desktop(desktop_path) {
        if (GLib.getenv("APPIMAGE") == null || GLib.getenv("APPIMAGE") == "") return false
        if (GLib.getenv(DOUGH_DESKTOP_RELAUNCH_ENV) == "1") return false
        if (GLib.getenv("DOUGH_DISABLE_DESKTOP_RELAUNCH") == "1") return false

        try {
            local info = Gio.DesktopAppInfo.new(DOUGH_APP_ID + ".desktop")
            if (info == null) info = Gio.DesktopAppInfo.new_from_filename(desktop_path)
            if (info == null) return false
            return info.launch(null, null)
        } catch (e) {
            print("desktop relaunch warning: " + e + "\n")
            return false
        }
    }

    // GNOME/Wayland resolves dock icons through a desktop file visible to the shell.
    function install_appimage_desktop_entry() {
        local appimage = GLib.getenv("APPIMAGE")
        if (appimage == null || appimage == "") return null

        local data_dir = GLib.get_user_data_dir()
        local appdir = GLib.getenv("SQGI_APPDIR")
        if (data_dir == null || data_dir == "" || appdir == null || appdir == "") return null

        try {
            local desktop_dir = GLib.build_filenamev([data_dir, "applications"])
            local icon_dir = GLib.build_filenamev([data_dir, "icons", "hicolor", "256x256", "apps"])
            GLib.mkdir_with_parents(desktop_dir, 493)
            GLib.mkdir_with_parents(icon_dir, 493)

            local desktop_path = GLib.build_filenamev([desktop_dir, DOUGH_APP_ID + ".desktop"])
            local icon_path = GLib.build_filenamev([icon_dir, DOUGH_ICON_NAME + ".png"])
            local desktop_icon = DOUGH_ICON_NAME

            this.remove_owned_desktop_file(GLib.build_filenamev([desktop_dir, "dough.desktop"]))

            local icon_candidates = [
                GLib.build_filenamev([appdir, "usr", "share", "icons", "hicolor", "256x256", "apps", DOUGH_ICON_NAME + ".png"]),
                GLib.build_filenamev([appdir, DOUGH_ICON_NAME + ".png"]),
                GLib.build_filenamev([appdir, "assets", DOUGH_ICON_NAME + ".png"]),
                GLib.build_filenamev([appdir, "assets", "icon.png"]),
                GLib.build_filenamev([GLib.get_current_dir(), "assets", DOUGH_ICON_NAME + ".png"]),
                GLib.build_filenamev([GLib.get_current_dir(), "assets", "icon.png"])
            ]
            foreach (src_path in icon_candidates) {
                if (!this.path_exists(src_path)) continue
                Gio.File.new_for_path(src_path).copy(
                    Gio.File.new_for_path(icon_path),
                    Gio.FileCopyFlags.overwrite,
                    null,
                    null
                )
                desktop_icon = icon_path
                break
            }

            local desktop =
                "[Desktop Entry]\n" +
                "Type=Application\n" +
                "Name=" + DOUGH_APP_NAME + "\n" +
                "Exec=" + this.desktop_launch_exec(appimage) + "\n" +
                "Icon=" + desktop_icon + "\n" +
                "Categories=Office;Finance;GTK;\n" +
                "Terminal=false\n" +
                "StartupNotify=true\n" +
                "StartupWMClass=" + DOUGH_APP_ID + "\n" +
                "X-Dough-AppImage=true\n"

            GLib.file_set_contents(desktop_path, desktop, -1)
            GLib.chmod(desktop_path, 493)

            return desktop_path
        } catch (e) {
            print("desktop integration warning: " + e + "\n")
        }
        return null
    }

    function install_css() {
        local display = Gdk.Display.get_default()
        if (display == null) return

        local provider = Gtk.CssProvider.new()
        local css =
            ".dough-shell { background: @theme_bg_color; }" +
            ".dough-nav { padding: 8px; border-bottom: 1px solid @borders; background: @theme_base_color; }" +
            ".dough-nav button { margin-right: 3px; }" +
            ".dough-nav button.dough-nav-active { background: @theme_selected_bg_color; color: @theme_selected_fg_color; }" +
            ".dough-content { background: @theme_bg_color; }" +
            ".dough-setup { padding: 10px 14px; border-bottom: 1px solid @borders; background: @theme_base_color; }" +
            ".dough-setup-panel { padding: 4px 0 4px 14px; border-left: 1px solid @borders; }" +
            ".dough-good { color: #1f7a4d; }" +
            ".dough-warning { color: #a35a00; }" +
            ".dough-danger { color: #a32020; }" +
            ".dough-status { padding: 6px 10px; border-top: 1px solid @borders; background: @theme_base_color; }" +
            ".dough-overlay-scrim { background: rgba(0, 0, 0, 0.42); }" +
            ".dough-dialog-card { background: @theme_bg_color; border: 1px solid @borders; border-radius: 8px; box-shadow: 0 12px 30px rgba(0, 0, 0, 0.30); }" +
            ".dough-dialog-header { padding: 10px 12px; border-bottom: 1px solid @borders; }"
        try {
            provider.load_from_string(css)
        } catch (_) {
            provider.load_from_data(css, css.len())
        }
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    }

    function build_shell() {
        local shell = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        shell.add_css_class("dough-shell")

        shell.append(this.build_navigation())

        this.content_area = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        this.content_area.set_hexpand(true)
        this.content_area.set_vexpand(true)
        this.content_area.add_css_class("dough-content")
        shell.append(this.content_area)

        this.status_label = Gtk.Label.new("Spinodb: " + this.repository.db_path)
        this.status_label.set_xalign(0.0)
        this.status_label.add_css_class("dim-label")
        this.status_label.add_css_class("dough-status")
        shell.append(this.status_label)

        return shell
    }

    function tooltip_text_for_control(widget) {
        local css_name = ""
        try {
            css_name = widget.get_css_name()
        } catch (e) {
            return null
        }

        if (css_name == "entry") {
            try {
                local placeholder = widget.get_placeholder_text()
                if (placeholder != null && placeholder.len() > 0) return placeholder
            } catch (e) {}
        }

        if (css_name == "button" || css_name == "checkbutton") {
            try {
                local label = widget.get_label()
                if (label != null && label.len() > 0) return label
            } catch (e) {}
        }

        if (css_name == "dropdown") return "Choose an option"
        return null
    }

    function tooltip_is_empty(widget) {
        try {
            local text = widget.get_tooltip_text()
            return text == null || text.len() == 0
        } catch (e) {
            return false
        }
    }

    function apply_tooltip_if_missing(widget, text) {
        if (widget == null || text == null || text.len() == 0) return widget
        if (this.tooltip_is_empty(widget)) widget.set_tooltip_text(text)
        return widget
    }

    function apply_default_tooltips(widget) {
        if (widget == null) return
        this.apply_tooltip_if_missing(widget, this.tooltip_text_for_control(widget))

        local child = null
        try {
            child = widget.get_first_child()
        } catch (e) {
            child = null
        }

        while (child != null) {
            this.apply_default_tooltips(child)
            try {
                child = child.get_next_sibling()
            } catch (e) {
                child = null
            }
        }
    }

    function nav_button(text, icon_name, callback) {
        local button = this.ui.action_button(text, icon_name, callback, "Open the " + text + " page.")
        button.add_css_class("flat")
        return button
    }

    function nav_page_button(page_id, text, icon_name, callback) {
        local button = this.nav_button(text, icon_name, callback)
        this.nav_buttons[page_id] <- button
        return button
    }

    function build_navigation() {
        this.nav_buttons = {}
        local nav = Gtk.Box.new(Gtk.Orientation.horizontal, 6)
        nav.add_css_class("dough-nav")

        nav.append(this.nav_page_button("dashboard", "Dashboard", "icon.png", function() { this.show_dashboard() }.bindenv(this)))
        nav.append(this.nav_page_button("accounts", "Accounts", "books.png", function() { this.show_accounts() }.bindenv(this)))
        nav.append(this.nav_page_button("transactions", "Transactions", "report.png", function() { this.show_transactions() }.bindenv(this)))
        nav.append(this.nav_page_button("import", "Import", "report.png", function() { this.show_import_options() }.bindenv(this)))
        nav.append(this.nav_page_button("budget", "Budget", "budget.png", function() { this.show_budget() }.bindenv(this)))
        nav.append(this.nav_page_button("report", "Report", "report.png", function() { this.show_budget_report() }.bindenv(this)))
        nav.append(this.nav_page_button("envelopes", "Envelopes", "envelope.png", function() { this.show_envelopes() }.bindenv(this)))
        nav.append(this.nav_page_button("line", "Line", "linegraph.png", function() { this.show_graph("Line Graphs", "linegraph.png") }.bindenv(this)))
        nav.append(this.nav_page_button("pie", "Pie", "piechart.png", function() { this.show_graph("Pie Charts", "piechart.png") }.bindenv(this)))
        nav.append(this.nav_page_button("options", "Options", "interface.png", function() { this.show_options() }.bindenv(this)))

        local scroll = Gtk.ScrolledWindow.new()
        scroll.set_policy(Gtk.PolicyType.automatic, Gtk.PolicyType.never)
        scroll.set_child(nav)
        return scroll
    }

    function page_id_for_title(title) {
        if (title == "Dashboard") return "dashboard"
        if (title == "Accounts") return "accounts"
        if (title == "Transactions") return "transactions"
        if (title == "Import Transactions") return "import"
        if (title == "Edit Budget") return "budget"
        if (title == "Budget Report") return "report"
        if (title == "Envelopes") return "envelopes"
        if (title == "Line Graphs") return "line"
        if (title == "Pie Charts") return "pie"
        if (title == "Options") return "options"
        return null
    }

    function set_active_page(page_id) {
        if (this.active_page_id != null && this.active_page_id in this.nav_buttons)
            this.nav_buttons[this.active_page_id].remove_css_class("dough-nav-active")
        this.active_page_id = page_id
        if (this.active_page_id != null && this.active_page_id in this.nav_buttons)
            this.nav_buttons[this.active_page_id].add_css_class("dough-nav-active")
    }

    function clear_children(container) {
        local child = container.get_first_child()
        while (child != null) {
            container.remove(child)
            child = container.get_first_child()
        }
    }

    function show_page(title, child, page_id = null) {
        if (this.content_area == null) return null

        this.close_tutorial_popover()
        this.close_overlay()
        this.clear_children(this.content_area)
        child.set_hexpand(true)
        child.set_vexpand(true)
        this.apply_default_tooltips(child)
        this.content_area.append(child)

        if (this.page_title_label != null) this.page_title_label.set_text(title)
        this.set_active_page(page_id != null ? page_id : this.page_id_for_title(title))
        this.refresh_title()
        return { close = function() {} }
    }

    function close_overlay() {
        if (this.app_overlay != null && this.overlay_layer != null) {
            this.app_overlay.remove_overlay(this.overlay_layer)
            this.overlay_layer = null
        }
    }

    function show_overlay(title, child, width = 760, height = 520) {
        if (this.app_overlay == null) return this.show_page(title, child)

        this.close_overlay()

        local layer = Gtk.Overlay.new()
        layer.set_hexpand(true)
        layer.set_vexpand(true)
        layer.set_halign(Gtk.Align.fill)
        layer.set_valign(Gtk.Align.fill)
        layer.set_focusable(true)

        local key_controller = Gtk.EventControllerKey.new()
        key_controller.connect("key-pressed", function(_, keyval, keycode, state) {
            if (keyval == Gdk.KEY_Escape) {
                this.close_overlay()
                return true
            }
            return false
        }.bindenv(this))
        layer.add_controller(key_controller)

        local scrim = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        scrim.set_hexpand(true)
        scrim.set_vexpand(true)
        scrim.add_css_class("dough-overlay-scrim")
        layer.set_child(scrim)

        local card = Gtk.Box.new(Gtk.Orientation.vertical, 0)
        card.set_size_request(width, height)
        card.set_halign(Gtk.Align.center)
        card.set_valign(Gtk.Align.center)
        card.add_css_class("dough-dialog-card")

        local header = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        header.add_css_class("dough-dialog-header")
        local title_label = Gtk.Label.new(title)
        title_label.set_xalign(0.0)
        title_label.set_hexpand(true)
        title_label.add_css_class("title-3")
        header.append(title_label)
        header.append(this.ui.plain_button("Close", function() { this.close_overlay() }.bindenv(this)))
        card.append(header)

        local scroll = Gtk.ScrolledWindow.new()
        scroll.set_hexpand(true)
        scroll.set_vexpand(true)
        scroll.set_child(child)
        card.append(scroll)

        this.apply_default_tooltips(card)

        layer.add_overlay(card)
        this.app_overlay.add_overlay(layer)
        this.overlay_layer = layer
        layer.grab_focus()

        return { close = function() { this.close_overlay() }.bindenv(this) }
    }

    function confirm_action(title, message, action, action_label = "Delete") {
        local root = this.ui.padded_box(Gtk.Orientation.vertical, 14, 18)
        root.append(this.ui.label(title, "title-3"))
        local copy = this.ui.label(message, "dim-label")
        copy.set_wrap(true)
        root.append(copy)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Cancel", function() {
            this.close_overlay()
        }.bindenv(this)))
        local confirm = this.ui.plain_button(action_label, function() {
            this.close_overlay()
            action()
        }.bindenv(this))
        confirm.add_css_class("destructive-action")
        actions.append(confirm)
        root.append(actions)

        return this.show_overlay(title, root, 520, 240)
    }

    function valid_period_settings() {
        if (this.document.start_date == null || this.document.start_date.len() == 0) return false
        return this.document.period_length == "weekly" ||
            this.document.period_length == "fortnightly" ||
            this.document.period_length == "monthly"
    }

    function envelope_count(type = null) {
        local count = 0
        local folders = []
        if (type == "income") folders = this.document.income_folders
        else if (type == "expense") folders = this.document.expense_folders
        else {
            foreach (folder in this.document.income_folders) folders.push(folder)
            foreach (folder in this.document.expense_folders) folders.push(folder)
        }

        foreach (folder in folders)
            count = count + folder.envelopes.len()
        return count
    }

    function setup_steps() {
        return [
            {
                id = "options",
                title = "Budget Frame",
                detail = "Currency, start date, and period length",
                done = this.valid_period_settings(),
                action = function() { this.show_options() }.bindenv(this)
            },
            {
                id = "envelopes",
                title = "Envelope Catalog",
                detail = "Income and expense categories with real envelope records",
                done = this.envelope_count("income") > 0 && this.envelope_count("expense") > 0,
                action = function() { this.show_envelopes() }.bindenv(this)
            },
            {
                id = "accounts",
                title = "Accounts",
                detail = "Where money lives and where transactions happen",
                done = this.document.accounts.len() > 0,
                action = function() { this.show_accounts() }.bindenv(this)
            },
            {
                id = "budget",
                title = "Current Period Budget",
                detail = "Income and expense envelopes allocated for this period",
                done = this.document.budgets.len() > 0,
                action = function() { this.show_budget() }.bindenv(this)
            },
            {
                id = "transactions",
                title = "Transactions",
                detail = "Actual activity tied to accounts and envelopes",
                done = this.document.transactions.len() > 0,
                action = function() { this.show_transactions() }.bindenv(this)
            },
            {
                id = "import",
                title = "Import Rules",
                detail = "Description patterns that can suggest envelopes",
                done = this.document.import_rules.len() > 0,
                action = function() { this.show_import_options() }.bindenv(this)
            }
        ]
    }

    function setup_complete_count() {
        local count = 0
        foreach (step in this.setup_steps())
            if (step.done) count = count + 1
        return count
    }

    function first_incomplete_setup_step() {
        foreach (step in this.setup_steps())
            if (!step.done) return step
        return null
    }

    function tutorial_steps() {
        return [
            {
                id = "options",
                title = "Set The Budget Frame",
                text = "Set the currency, start date, and period length before planning the current period.",
                action = function() { this.show_options() }.bindenv(this)
            },
            {
                id = "envelopes",
                title = "Create Envelopes",
                text = "Envelopes are the jobs you give your money. Keep the first catalog small and adjust it later.",
                action = function() { this.show_envelopes() }.bindenv(this)
            },
            {
                id = "accounts",
                title = "Add Accounts",
                text = "Accounts are where money lives. Transactions change account balances over time.",
                action = function() { this.show_accounts() }.bindenv(this)
            },
            {
                id = "budget",
                title = "Plan The Period",
                text = "The Budget page turns envelope categories into this period's income and expense plan.",
                action = function() { this.show_budget() }.bindenv(this)
            },
            {
                id = "transactions",
                title = "Record Activity",
                text = "Each transaction needs an account for where it happened and an envelope for what it was for.",
                action = function() { this.show_transactions() }.bindenv(this)
            },
            {
                id = "import",
                title = "Import Faster",
                text = "CSV/QIF import can use match rules to suggest envelopes from transaction descriptions.",
                action = function() { this.show_import_options() }.bindenv(this)
            },
            {
                id = "report",
                title = "Review Progress",
                text = "Reports compare your period plan with actual transactions so you can adjust calmly.",
                action = function() { this.show_budget_report() }.bindenv(this)
            }
        ]
    }

    function ensure_tutorial_state() {
        if (this.tutorial_state == null) {
            this.tutorial_state = {
                completed = false,
                dismissed = false,
                last_step = 0
            }
        }
    }

    function persist_tutorial_state(status = null) {
        this.ensure_tutorial_state()
        this.repository.save_tutorial_state(this.tutorial_state)
        if (status != null) this.set_status(status)
    }

    function mark_tutorial_progress(index) {
        this.ensure_tutorial_state()
        this.tutorial_state.last_step = index
        this.persist_tutorial_state()
    }

    function mark_tutorial_completed() {
        this.ensure_tutorial_state()
        this.tutorial_state.completed = true
        this.tutorial_state.dismissed = false
        this.tutorial_state.last_step = this.tutorial_steps().len()
        this.persist_tutorial_state("Guide complete. You can restart it from the header.")
    }

    function mark_tutorial_dismissed() {
        this.ensure_tutorial_state()
        this.tutorial_state.dismissed = true
        this.tutorial_state.last_step = this.tutorial_step_index
        this.persist_tutorial_state("Guide skipped. You can restart it from the header.")
    }

    function should_offer_tutorial() {
        this.ensure_tutorial_state()
        if (this.tutorial_state.completed || this.tutorial_state.dismissed) return false
        if (this.tutorial_state.last_step > 0) return false
        return this.first_incomplete_setup_step() != null
    }

    function maybe_offer_tutorial() {
        if (!this.should_offer_tutorial()) return
        if (this.tutorial_button == null) return

        this.close_tutorial_popover()
        local pop = Gtk.Popover.new()
        pop.set_parent(this.tutorial_button)
        pop.set_has_arrow(true)
        pop.set_position(Gtk.PositionType.bottom)

        local root = this.ui.padded_box(Gtk.Orientation.vertical, 10, 12)
        root.set_size_request(340, -1)
        root.append(this.ui.label("Guided Setup", "title-3"))
        local copy = this.ui.label("Dough can walk you through options, envelopes, accounts, budgets, transactions, and import rules.", "dim-label")
        copy.set_wrap(true)
        root.append(copy)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Later", function() {
            this.close_tutorial_popover()
            this.mark_tutorial_dismissed()
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Start", function() {
            this.close_tutorial_popover()
            this.start_tutorial()
        }.bindenv(this)))
        root.append(actions)

        pop.set_child(root)
        this.tutorial_popover = pop
        pop.popup()
    }

    function close_tutorial_popover() {
        if (this.tutorial_popover != null) {
            this.tutorial_popover.popdown()
            this.tutorial_popover.unparent()
            this.tutorial_popover = null
        }
    }

    function start_tutorial(from_gap = false) {
        local start = 0
        if (from_gap) {
            local incomplete = this.first_incomplete_setup_step()
            local steps = this.tutorial_steps()
            if (incomplete != null) {
                for (local i = 0; i < steps.len(); i = i + 1) {
                    if (steps[i].id == incomplete.id) {
                        start = i
                        break
                    }
                }
            }
        }
        this.show_tutorial_step(start)
    }

    function show_tutorial_step(index) {
        local steps = this.tutorial_steps()
        if (index < 0) index = 0
        if (index >= steps.len()) {
            this.close_tutorial_popover()
            this.show_dashboard()
            this.mark_tutorial_completed()
            return
        }

        this.close_tutorial_popover()
        this.tutorial_step_index = index
        this.mark_tutorial_progress(index)

        local step = steps[index]
        step.action()

        local anchor = this.tutorial_button
        if (step.id in this.nav_buttons) anchor = this.nav_buttons[step.id]
        if (anchor == null) return

        local pop = Gtk.Popover.new()
        pop.set_parent(anchor)
        pop.set_has_arrow(true)
        pop.set_position(Gtk.PositionType.bottom)

        local root = this.ui.padded_box(Gtk.Orientation.vertical, 10, 12)
        root.set_size_request(320, -1)
        root.append(this.ui.label(step.title, "title-3"))
        local copy = this.ui.label(step.text, "dim-label")
        copy.set_wrap(true)
        root.append(copy)

        local counter = this.ui.label((index + 1) + "/" + steps.len(), "dim-label")
        root.append(counter)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local back = this.ui.plain_button("Back", function() {
            this.show_tutorial_step(this.tutorial_step_index - 1)
        }.bindenv(this))
        back.set_sensitive(index > 0)
        actions.append(back)
        actions.append(this.ui.plain_button("Skip", function() {
            this.close_tutorial_popover()
            this.mark_tutorial_dismissed()
        }.bindenv(this)))
        actions.append(this.ui.plain_button(index == steps.len() - 1 ? "Done" : "Next", function() {
            this.show_tutorial_step(this.tutorial_step_index + 1)
        }.bindenv(this)))
        root.append(actions)

        pop.set_child(root)
        this.tutorial_popover = pop
        pop.popup()
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
            paths.push("")
            labels.push(type == "income" ? "No income envelopes" : "No expense envelopes")
        }

        return { paths = paths, labels = labels }
    }

    function budget_envelope_options(type, budget) {
        local opts = this.envelope_options(type)
        local path = this.envelope_path(budget.folder_id, budget.envelope_id)
        if (path.len() == 0) return opts
        if (this.document.find_envelope(type, budget.folder_id, budget.envelope_id) != null)
            return opts

        local paths = [path]
        local labels = ["Missing: " + path]
        foreach (item in opts.paths) paths.push(item)
        foreach (item in opts.labels) labels.push(item)
        return { paths = paths, labels = labels }
    }

    function rule_envelope_options(rule) {
        local opts = this.envelope_options(rule.type)
        local path = this.envelope_path(rule.folder_id, rule.envelope_id)
        if (path.len() == 0) return opts
        if (this.document.find_envelope(rule.type, rule.folder_id, rule.envelope_id) != null)
            return opts

        local paths = [path]
        local labels = ["Missing: " + path]
        foreach (item in opts.paths) paths.push(item)
        foreach (item in opts.labels) labels.push(item)
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

    function import_rule_target_label(rule) {
        if (rule == null) return ""
        local folder = this.document.folder_label(rule.type, rule.folder_id)
        local envelope = this.document.envelope_label(rule.type, rule.folder_id, rule.envelope_id, "")
        if (folder.len() > 0 && envelope.len() > 0) return folder + " / " + envelope
        if (rule.folder_id.len() > 0 || rule.envelope_id.len() > 0)
            return rule.folder_id + "/" + rule.envelope_id
        return "No target"
    }

    function transaction_review_status(txn) {
        if (txn.type == "transfer")
            return { text = "Transfer - no envelope needed", css = "dim-label" }

        local envelope = this.document.find_envelope(txn.type, txn.folder_id, txn.envelope_id)
        if (envelope == null)
            return { text = "Needs envelope", css = "dough-danger" }

        if (txn.splits.len() > 0)
            return { text = "Split across " + txn.splits.len() + " envelopes", css = "dough-warning" }

        local rule = this.match_import_rule(txn.description, txn.type)
        if (rule != null) {
            if (rule.type == txn.type && rule.folder_id == txn.folder_id && rule.envelope_id == txn.envelope_id)
                return { text = "Rule match: " + rule.name, css = "dough-good" }
            return { text = "Rule suggests: " + this.import_rule_target_label(rule), css = "dough-warning" }
        }

        return { text = "Manual assignment", css = "dim-label" }
    }

    function transaction_amount_label(txn) {
        local prefix = txn.type == "income" ? "+" : "-"
        if (txn.type == "transfer") prefix = "-"
        return prefix + this.money(txn.amount)
    }

    function parse_iso_date_parts(text) {
        local value = this.trim(text)
        if (value.len() < 10) return null
        if (value.slice(4, 5) != "-" || value.slice(7, 8) != "-") return null

        local year_text = value.slice(0, 4)
        local month_text = value.slice(5, 7)
        local day_text = value.slice(8, 10)
        if (!this.only_digits(year_text) || !this.only_digits(month_text) || !this.only_digits(day_text))
            return null

        try {
            return {
                year = year_text.tointeger(),
                month = month_text.tointeger(),
                day = day_text.tointeger()
            }
        } catch (e) {
            return null
        }
    }

    function is_digit(ch) {
        return ch >= "0" && ch <= "9"
    }

    function only_digits(text) {
        if (text == null || text.len() == 0) return false
        for (local i = 0; i < text.len(); i = i + 1) {
            if (!this.is_digit(text.slice(i, i + 1))) return false
        }
        return true
    }

    function expand_date_year(year) {
        if (year < 100) return year >= 70 ? 1900 + year : 2000 + year
        return year
    }

    function date_from_parts(year, month, day) {
        if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null
        try {
            local date = GLib.DateTime.new(GLib.TimeZone.new_utc(), year, month, day, 0, 0, 0.0)
            if (date == null) return null
            if (date.get_year() != year || date.get_month() != month || date.get_day_of_month() != day)
                return null
            return date
        } catch (e) {
            return null
        }
    }

    function iso_date_time(text) {
        local parts = this.parse_iso_date_parts(text)
        if (parts == null) return null
        return this.date_from_parts(parts.year, parts.month, parts.day)
    }

    function date_number_groups(text) {
        local groups = []
        local part = ""
        for (local i = 0; i < text.len(); i = i + 1) {
            local ch = text.slice(i, i + 1)
            if (this.is_digit(ch)) {
                part += ch
            } else if (part.len() > 0) {
                groups.push(part)
                part = ""
            }
        }
        if (part.len() > 0) groups.push(part)
        return groups
    }

    function prefer_month_first_dates() {
        return this.document != null && this.document.date_format != null &&
            this.document.date_format.find("MM") == 0
    }

    function format_date_candidate(year, month, day) {
        local date = this.date_from_parts(this.expand_date_year(year), month, day)
        if (date == null) return null
        return date.format("%Y-%m-%d")
    }

    function normalized_date_text(text, fallback = null) {
        local value = this.trim(text)
        if (value.len() == 0) return fallback

        local iso = this.iso_date_time(value)
        if (iso != null) return iso.format("%Y-%m-%d")

        local groups = this.date_number_groups(value)
        if (groups.len() == 1 && groups[0].len() == 8) {
            local compact = groups[0]
            return this.format_date_candidate(
                compact.slice(0, 4).tointeger(),
                compact.slice(4, 6).tointeger(),
                compact.slice(6, 8).tointeger())
        }

        if (groups.len() < 3) return fallback

        local a = groups[0].tointeger()
        local b = groups[1].tointeger()
        local c = groups[2].tointeger()
        if (groups[0].len() == 4) return this.format_date_candidate(a, b, c)

        local month_first = this.prefer_month_first_dates()
        if (a > 12 && b <= 12) month_first = false
        else if (b > 12 && a <= 12) month_first = true

        local normalized = month_first ?
            this.format_date_candidate(c, a, b) :
            this.format_date_candidate(c, b, a)
        if (normalized != null) return normalized

        return month_first ?
            this.format_date_candidate(c, b, a) :
            this.format_date_candidate(c, a, b)
    }

    function select_calendar_date(calendar, text) {
        local date = this.iso_date_time(this.normalized_date_text(text, ""))
        if (date == null) date = this.iso_date_time(this.document.start_date)
        if (date != null) calendar.select_day(date)
    }

    function next_period_start(date) {
        if (date == null) return null
        if (this.document.period_length == "weekly") return date.add_days(7)
        if (this.document.period_length == "fortnightly") return date.add_days(14)
        return date.add_months(1)
    }

    function current_period_start_iso() {
        local date = this.iso_date_time(this.document.start_date)
        if (date == null) return this.document.start_date
        for (local i = 0; i < this.document.period_index; i = i + 1)
            date = this.next_period_start(date)
        return date.format("%Y-%m-%d")
    }

    function current_period_end_iso() {
        local start = this.iso_date_time(this.current_period_start_iso())
        local next = this.next_period_start(start)
        if (next == null) return this.current_period_start_iso()
        return next.add_days(-1).format("%Y-%m-%d")
    }

    function calendar_iso_date(calendar) {
        local date = calendar.get_date()
        if (date == null) return ""
        return date.format("%Y-%m-%d")
    }

    function show_date_picker(entry, anchor) {
        local pop = Gtk.Popover.new()
        pop.set_parent(anchor)
        pop.set_has_arrow(true)
        pop.set_position(Gtk.PositionType.bottom)

        local root = this.ui.padded_box(Gtk.Orientation.vertical, 8, 8)
        local calendar = Gtk.Calendar.new()
        this.select_calendar_date(calendar, entry.get_text())
        calendar.connect("day-selected", function() {
            entry.set_text(this.calendar_iso_date(calendar))
            pop.popdown()
            pop.unparent()
        }.bindenv(this))
        root.append(calendar)

        pop.set_child(root)
        pop.popup()
    }

    function date_picker(entry) {
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 6)
        entry.set_hexpand(true)
        this.apply_tooltip_if_missing(entry, "Enter a date as YYYY-MM-DD, or use the picker.")
        box.append(entry)

        local button = null
        button = this.ui.plain_button("Pick", function() {
            this.show_date_picker(entry, button)
        }.bindenv(this), "Open the calendar date picker.")
        box.append(button)
        return box
    }

    function labeled_control(label_text, control) {
        local row = Gtk.Box.new(Gtk.Orientation.horizontal, 10)
        local label = Gtk.Label.new(label_text)
        label.set_xalign(0.0)
        label.set_size_request(120, -1)
        row.append(label)
        this.apply_tooltip_if_missing(control, label_text)
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
        this.clear_children(list)
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

        local default_date = this.normalized_date_text(this.document.start_date, this.document.start_date)
        local normalized_date = this.normalized_date_text(date, default_date)
        local type = amount < 0.0 ? "expense" : "income"
        if (amount < 0.0) amount = amount * -1.0
        local rule = this.match_import_rule(description, type)
        local path_info = this.import_rule_envelope_path(rule, type)

        return Models.Transaction(
            this.make_id("import"),
            account_id != null && account_id.len() > 0 ? account_id : this.first_account_id(),
            normalized_date,
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

    function add_setup_step_row(list, step) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.vertical, 5)
        box.set_margin_top(7)
        box.set_margin_bottom(7)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local line = Gtk.Box.new(Gtk.Orientation.horizontal, 7)
        local status = Gtk.Label.new(step.done ? "[x]" : "[ ]")
        status.set_xalign(0.0)
        status.add_css_class(step.done ? "dough-good" : "dough-warning")
        line.append(status)

        local title = this.ui.label(step.title)
        title.set_hexpand(true)
        line.append(title)
        box.append(line)

        local detail = this.ui.label(step.detail, "dim-label")
        detail.set_wrap(true)
        box.append(detail)

        local action = this.ui.plain_button(step.done ? "Review" : "Open", function() {
            step.action()
        }.bindenv(this))
        action.set_halign(Gtk.Align.end)
        box.append(action)

        row.set_child(box)
        list.append(row)
    }

    function build_setup_checklist() {
        local steps = this.setup_steps()
        local missing = []
        foreach (step in steps)
            if (!step.done) missing.push(step)

        local root = Gtk.Box.new(Gtk.Orientation.vertical, 8)
        root.add_css_class("dough-setup-panel")
        root.set_size_request(280, -1)

        local header = Gtk.Box.new(Gtk.Orientation.vertical, 2)
        local title = this.ui.label("Setup", "title-3")
        header.append(title)
        header.append(this.ui.label(this.setup_complete_count() + "/" + steps.len() + " ready", "dim-label"))
        root.append(header)

        if (missing.len() == 0) {
            local ready = this.ui.label("All essentials are ready.", "dough-good")
            ready.set_wrap(true)
            root.append(ready)
        } else {
            local next = missing[0]
            local next_label = this.ui.label("Next: " + next.title, "dough-warning")
            next_label.set_wrap(true)
            root.append(next_label)

            local list = Gtk.ListBox.new()
            list.set_selection_mode(Gtk.SelectionMode.none)
            local visible = missing.len() > 3 ? 3 : missing.len()
            for (local i = 0; i < visible; i = i + 1)
                this.add_setup_step_row(list, missing[i])
            root.append(list)

            if (missing.len() > visible)
                root.append(this.ui.label((missing.len() - visible) + " more setup items", "dim-label"))
        }

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        if (missing.len() > 0) {
            actions.append(this.ui.plain_button("Open Next", function() {
                local step = this.first_incomplete_setup_step()
                if (step != null) step.action()
            }.bindenv(this)))
        }
        local resume_label = "Start Guide"
        if (missing.len() > 0) resume_label = "Resume Guide"
        else if (this.tutorial_state != null && this.tutorial_state.completed) resume_label = "Review Guide"
        actions.append(this.ui.plain_button(resume_label, function() { this.start_tutorial(true) }.bindenv(this)))
        root.append(actions)

        return root
    }

    function build_dashboard() {
        local root = Gtk.Box.new(Gtk.Orientation.vertical, 0)

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

        local body = Gtk.Box.new(Gtk.Orientation.horizontal, 14)
        body.set_margin_start(14)
        body.set_margin_end(14)
        body.set_margin_bottom(14)
        body.set_hexpand(true)
        body.set_vexpand(true)

        local scroll = Gtk.ScrolledWindow.new()
        scroll.set_hexpand(true)
        scroll.set_vexpand(true)
        this.dashboard_area = Gtk.DrawingArea.new()
        this.dashboard_area.set_size_request(720, 360)
        this.dashboard_area.set_draw_func(function(area, cr, width, height) {
            this.draw_dashboard(cr, width, height)
        }.bindenv(this), null, function(_) {})
        scroll.set_child(this.dashboard_area)
        body.append(scroll)
        body.append(this.build_setup_checklist())

        root.append(body)
        return root
    }

    function show_dashboard() {
        this.show_page("Dashboard", this.build_dashboard())
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
        return this.show_page(title, child)
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
        search_entry.set_tooltip_text("Filter transactions by description text.")
        local start_entry = Gtk.Entry.new()
        start_entry.set_placeholder_text("Start date")
        start_entry.set_tooltip_text("Only show transactions on or after this date.")
        local end_entry = Gtk.Entry.new()
        end_entry.set_placeholder_text("End date")
        end_entry.set_tooltip_text("Only show transactions on or before this date.")
        local account_filter = this.account_options(true, false)
        local account_filter_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_filter.labels), null)
        account_filter_dropdown.set_tooltip_text("Filter transactions by account.")
        local type_filter_values = ["", "income", "expense", "transfer"]
        local type_filter_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["All types", "Income", "Expense", "Transfer"]), null)
        type_filter_dropdown.set_tooltip_text("Filter transactions by transaction type.")
        local path_filter_entry = Gtk.Entry.new()
        path_filter_entry.set_placeholder_text("Envelope")
        path_filter_entry.set_tooltip_text("Filter transactions by envelope or folder text.")
        filter_box.append(search_entry)
        filter_box.append(this.date_picker(start_entry))
        filter_box.append(this.date_picker(end_entry))
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
            this.confirm_action(
                "Delete Account",
                "Delete " + this.account_label(account) + " and every transaction that uses it?",
                function() {
                    this.remove_array_item_by_id(this.document.accounts, account.id)
                    for (local i = this.document.transactions.len() - 1; i >= 0; i = i - 1) {
                        if (this.document.transactions[i].affects_account(account.id))
                            this.document.transactions.remove(i)
                    }
                    list.remove(row)
                    this.persist_document("Deleted account and related transactions.")
                }.bindenv(this),
                "Delete Account")
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
        local txn_date = this.normalized_date_text(txn.date, "")
        local normalized_start = this.normalized_date_text(start_date)
        local normalized_end = this.normalized_date_text(end_date)
        if (normalized_start != null && txn_date < normalized_start) return false
        if (normalized_end != null && txn_date > normalized_end) return false
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

        local date_label = Gtk.Label.new(this.normalized_date_text(txn.date, txn.date))
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
        local review = this.transaction_review_status(txn)
        local review_label = this.ui.label(review.text, review.css)
        review_label.set_wrap(true)
        details.append(review_label)
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
            this.confirm_action(
                "Delete Transaction",
                "Delete " + (txn.description.len() > 0 ? txn.description : "this transaction") + "?",
                function() {
                    this.remove_array_item_by_id(this.document.transactions, txn.id)
                    list.remove(row)
                    this.persist_document("Deleted transaction.")
                    if (refresh != null) refresh()
                }.bindenv(this),
                "Delete Transaction")
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
        date_entry.set_text(this.normalized_date_text(txn.date, txn.date))
        date_entry.set_tooltip_text("Transaction date in YYYY-MM-DD format.")
        root.append(this.labeled_control("Date", this.date_picker(date_entry)))

        local account_opts = this.account_options(false, true)
        local account_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_opts.labels), null)
        account_dropdown.set_selected(this.index_for_value(account_opts.ids, txn.account_id, 0))
        account_dropdown.set_tooltip_text("Choose the account where this transaction happened.")
        root.append(this.labeled_control("Account", account_dropdown))

        local type_values = ["income", "expense", "transfer"]
        local type_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Income", "Expense", "Transfer"]), null)
        type_dropdown.set_selected(this.index_for_value(type_values, txn.type, 1))
        type_dropdown.set_tooltip_text("Choose whether this is income, an expense, or a transfer.")
        root.append(this.labeled_control("Type", type_dropdown))

        local selected_type = this.dropdown_value(type_values, type_dropdown, txn.type)
        local envelope_opts = this.envelope_options(selected_type)
        local envelope_dropdown = Gtk.DropDown.new(Gtk.StringList.new(envelope_opts.labels), null)
        envelope_dropdown.set_selected(this.index_for_value(
            envelope_opts.paths,
            this.envelope_path(txn.folder_id, txn.envelope_id),
            0))
        envelope_dropdown.set_sensitive(selected_type != "transfer")
        envelope_dropdown.set_tooltip_text("Choose the envelope this transaction belongs to.")
        local envelope_row = this.labeled_control("Envelope", envelope_dropdown)
        root.append(envelope_row)

        local refresh_envelope_dropdown = function(preferred_path = null) {
            local current_type = this.dropdown_value(type_values, type_dropdown, txn.type)
            envelope_opts = this.envelope_options(current_type)
            envelope_dropdown.set_model(Gtk.StringList.new(envelope_opts.labels))
            local wanted = preferred_path != null ? preferred_path :
                this.envelope_path(txn.folder_id, txn.envelope_id)
            envelope_dropdown.set_selected(this.index_for_value(envelope_opts.paths, wanted, 0))
            envelope_dropdown.set_sensitive(current_type != "transfer")
        }.bindenv(this)

        local description_entry = Gtk.Entry.new()
        description_entry.set_text(txn.description)
        description_entry.set_tooltip_text("Human-readable transaction description.")
        root.append(this.labeled_control("Description", description_entry))

        local amount_entry = Gtk.Entry.new()
        amount_entry.set_text(this.amount_text(txn.amount))
        amount_entry.set_tooltip_text("Transaction amount without currency symbol.")
        root.append(this.labeled_control("Amount", amount_entry))

        local transfer_opts = this.account_options(false, true)
        local transfer_dropdown = Gtk.DropDown.new(Gtk.StringList.new(transfer_opts.labels), null)
        transfer_dropdown.set_selected(this.index_for_value(transfer_opts.ids, txn.transfer_account_id, 0))
        transfer_dropdown.set_tooltip_text("Choose the destination account for transfers.")
        local transfer_row = this.labeled_control("Transfer to", transfer_dropdown)
        root.append(transfer_row)

        local refresh_transaction_editor_visibility = function() {
            local current_type = this.dropdown_value(type_values, type_dropdown, txn.type)
            envelope_row.set_visible(current_type != "transfer")
            transfer_row.set_visible(current_type == "transfer")
        }.bindenv(this)

        type_dropdown.connect("notify::selected", function(_) {
            refresh_envelope_dropdown()
            refresh_transaction_editor_visibility()
        })
        refresh_transaction_editor_visibility()

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.set_halign(Gtk.Align.end)
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
        }.bindenv(this), "Use import match rules to suggest an envelope."))

        local dialog = null
        actions.append(this.ui.plain_button("Save", function() {
            local amount = this.parse_amount(amount_entry.get_text())
            if (amount == null) {
                this.set_status("Enter a valid transaction amount.")
                return
            }

            local normalized_date = this.normalized_date_text(date_entry.get_text())
            if (normalized_date == null) {
                this.set_status("Choose a valid transaction date.")
                return
            }

            date_entry.set_text(normalized_date)
            txn.date = normalized_date
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
            if (dialog != null) dialog.close()
        }.bindenv(this), "Save this transaction."))
        root.append(actions)

        dialog = this.show_overlay(add_on_save ? "Add Transaction" : "Edit Transaction", root, 720, 620)
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
        this.show_overlay("Transaction Splits", root, 760, 420)
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
        path_entry.set_tooltip_text("Path to the CSV or QIF file to import.")
        local format_list = Gtk.StringList.new(["CSV", "QIF"])
        local format_dropdown = Gtk.DropDown.new(format_list, null)
        format_dropdown.set_tooltip_text("Choose the import file format.")
        local account_opts = this.account_options(false, true)
        local account_dropdown = Gtk.DropDown.new(Gtk.StringList.new(account_opts.labels), null)
        account_dropdown.set_selected(this.index_for_value(account_opts.ids, this.first_account_id(), 0))
        account_dropdown.set_tooltip_text("Choose the account imported transactions belong to.")
        source_box.append(path_entry)
        source_box.append(this.ui.plain_button("Choose & Import", function() {
            this.choose_import_file(path_entry, format_dropdown, function(path) {
                if (run_import != null) run_import()
            })
        }.bindenv(this), "Choose a CSV or QIF file and import it immediately."))
        source_box.append(format_dropdown)
        source_box.append(account_dropdown)
        root.append(source_box)

        local csv_box = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local date_col = Gtk.Entry.new()
        date_col.set_placeholder_text("Date col")
        date_col.set_text("0")
        date_col.set_tooltip_text("Zero-based CSV column index containing the transaction date.")
        local description_col = Gtk.Entry.new()
        description_col.set_placeholder_text("Description col")
        description_col.set_text("1")
        description_col.set_tooltip_text("Zero-based CSV column index containing the transaction description.")
        local amount_col = Gtk.Entry.new()
        amount_col.set_placeholder_text("Amount col")
        amount_col.set_text("2")
        amount_col.set_tooltip_text("Zero-based CSV column index containing signed transaction amounts.")
        local memo_col = Gtk.Entry.new()
        memo_col.set_placeholder_text("Memo col")
        memo_col.set_tooltip_text("Optional zero-based CSV column index for memo text.")
        local debit_col = Gtk.Entry.new()
        debit_col.set_placeholder_text("Debit col")
        debit_col.set_tooltip_text("Optional zero-based CSV column index for debit amounts.")
        local credit_col = Gtk.Entry.new()
        credit_col.set_placeholder_text("Credit col")
        credit_col.set_tooltip_text("Optional zero-based CSV column index for credit amounts.")
        local skip_header = Gtk.CheckButton.new_with_label("Header row")
        skip_header.set_active(true)
        skip_header.set_tooltip_text("Skip the first CSV row when it contains column names.")
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
        }.bindenv(this), "Import transactions using the current settings."))
        import_actions.append(this.ui.plain_button("Export QIF", function() {
            this.export_qif(path_entry.get_text())
        }.bindenv(this), "Export current transactions to the path above in QIF format."))
        root.append(import_actions)
        root.append(import_status)

        root.append(this.ui.label("Envelope Match Rules", "title-3"))
        local rules_data = this.ui.scrolled_list()
        this.populate_import_rule_rows(rules_data.list)
        root.append(rules_data.scroll)

        local rule_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        rule_actions.append(this.ui.plain_button("Add Rule", function() {
            local path = this.first_envelope_path("expense")
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
        }.bindenv(this), "Add a regex rule that assigns matching transactions to an envelope."))
        rule_actions.append(this.ui.plain_button("Reset Defaults", function() {
            this.confirm_action(
                "Reset Match Rules",
                "Replace all current import match rules with the default rules?",
                function() {
                    this.document.import_rules = []
                    Models.ensure_default_import_rules(this.document)
                    this.populate_import_rule_rows(rules_data.list)
                    this.persist_document("Restored default import match rules.")
                }.bindenv(this),
                "Reset Rules")
        }.bindenv(this), "Replace match rules with Dough's default starter rules."))
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
        local box = Gtk.Box.new(Gtk.Orientation.vertical, 7)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        if (rule.type != "income" && rule.type != "expense")
            rule.type = "expense"

        local header = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        local enabled = Gtk.CheckButton.new_with_label("On")
        enabled.set_active(rule.enabled)
        enabled.set_tooltip_text("Enable or disable this match rule.")
        enabled.connect("toggled", function() {
            rule.enabled = enabled.get_active()
            this.persist_document()
        }.bindenv(this))
        header.append(enabled)

        local name_entry = Gtk.Entry.new()
        name_entry.set_hexpand(true)
        name_entry.set_placeholder_text("Name")
        name_entry.set_text(rule.name)
        name_entry.set_tooltip_text("Short label for this match rule.")
        name_entry.connect("changed", function() {
            rule.name = name_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        header.append(name_entry)

        local priority_entry = Gtk.Entry.new()
        priority_entry.set_placeholder_text("Priority")
        priority_entry.set_text("" + rule.priority)
        priority_entry.set_tooltip_text("Lower numbers run first when multiple rules match.")
        priority_entry.connect("changed", function() {
            rule.priority = this.parse_column_index(priority_entry.get_text(), rule.priority)
            this.persist_document()
        }.bindenv(this))
        header.append(priority_entry)

        header.append(this.ui.plain_button("Delete", function() {
            this.confirm_action(
                "Delete Match Rule",
                "Delete the import match rule " + rule.name + "?",
                function() {
                    this.remove_array_item_by_id(this.document.import_rules, rule.id)
                    list.remove(row)
                    this.persist_document("Deleted import match rule.")
                }.bindenv(this),
                "Delete Rule")
        }.bindenv(this)))
        box.append(header)

        local pattern_row = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        pattern_row.append(this.ui.label("Pattern", "dim-label"))
        local pattern_entry = Gtk.Entry.new()
        pattern_entry.set_hexpand(true)
        pattern_entry.set_placeholder_text("Regex pattern")
        pattern_entry.set_text(rule.pattern)
        pattern_entry.set_tooltip_text("Regular expression matched against transaction descriptions.")
        pattern_entry.connect("changed", function() {
            rule.pattern = pattern_entry.get_text()
            this.persist_document()
        }.bindenv(this))
        pattern_row.append(pattern_entry)
        local test_entry = Gtk.Entry.new()
        test_entry.set_placeholder_text("Test text")
        test_entry.set_tooltip_text("Sample transaction description to test against this pattern.")
        pattern_row.append(test_entry)
        pattern_row.append(this.ui.plain_button("Test", function() {
            local matched = this.regex_matches(pattern_entry.get_text(), test_entry.get_text())
            local target = this.import_rule_target_label(rule)
            this.set_status(rule.name + ": " + (matched ? "matched -> " + target : "no match"))
        }.bindenv(this), "Test this regex against the sample text."))
        box.append(pattern_row)

        local target_row = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        target_row.append(this.ui.label("Target", "dim-label"))
        local type_values = ["expense", "income"]
        local type_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Expense", "Income"]), null)
        type_dropdown.set_selected(this.index_for_value(type_values, rule.type, 0))
        type_dropdown.set_tooltip_text("Choose whether this rule targets expense or income envelopes.")
        target_row.append(type_dropdown)

        local envelope_opts = this.rule_envelope_options(rule)
        local envelope_dropdown = Gtk.DropDown.new(Gtk.StringList.new(envelope_opts.labels), null)
        envelope_dropdown.set_hexpand(true)
        envelope_dropdown.set_selected(this.index_for_value(
            envelope_opts.paths,
            this.envelope_path(rule.folder_id, rule.envelope_id),
            0))
        envelope_dropdown.set_tooltip_text("Choose the envelope assigned when this rule matches.")
        target_row.append(envelope_dropdown)

        local target_status = this.ui.label(this.import_rule_target_label(rule), "dim-label")
        target_status.set_hexpand(true)
        target_row.append(target_status)

        local apply_rule_target = function() {
            local selected_type = this.dropdown_value(type_values, type_dropdown, rule.type)
            local path_text = this.dropdown_value(envelope_opts.paths, envelope_dropdown, "")
            if (path_text.len() == 0) {
                rule.type = selected_type
                rule.folder_id = ""
                rule.envelope_id = ""
                target_status.set_text("No target")
                this.persist_document()
                this.set_status("Choose an envelope target for " + rule.name + ".")
                return
            }

            local slash = path_text.find("/")
            if (slash == null) return
            local folder_id = path_text.slice(0, slash)
            local envelope_id = path_text.slice(slash + 1)
            local envelope = this.document.find_envelope(selected_type, folder_id, envelope_id)
            if (envelope == null) {
                target_status.set_text("Missing: " + path_text)
                this.set_status("Rule target is not a real envelope: " + path_text)
                return
            }

            rule.type = selected_type
            rule.folder_id = folder_id
            rule.envelope_id = envelope_id
            target_status.set_text(this.import_rule_target_label(rule))
            this.persist_document()
        }.bindenv(this)

        local refresh_rule_envelope_dropdown = function() {
            local selected_type = this.dropdown_value(type_values, type_dropdown, rule.type)
            envelope_opts = selected_type == rule.type ?
                this.rule_envelope_options(rule) :
                this.envelope_options(selected_type)
            envelope_dropdown.set_model(Gtk.StringList.new(envelope_opts.labels))
            local wanted = selected_type == rule.type ?
                this.envelope_path(rule.folder_id, rule.envelope_id) : ""
            envelope_dropdown.set_selected(this.index_for_value(envelope_opts.paths, wanted, 0))
        }.bindenv(this)

        type_dropdown.connect("notify::selected", function(_) {
            refresh_rule_envelope_dropdown()
            apply_rule_target()
        })
        envelope_dropdown.connect("notify::selected", function(_) {
            apply_rule_target()
        })
        box.append(target_row)

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

        local income_data = this.ui.scrolled_list()
        local expense_data = this.ui.scrolled_list()
        local income_count = 0
        local expense_count = 0
        foreach (item in this.document.budgets) {
            if (item.type == "income") {
                income_count = income_count + 1
                this.add_budget_editor_row(income_data.list, item, refresh_budget)
            } else {
                expense_count = expense_count + 1
                this.add_budget_editor_row(expense_data.list, item, refresh_budget)
            }
        }
        if (income_count == 0) this.add_empty_list_row(income_data.list, "No income planned for this period.")
        if (expense_count == 0) this.add_empty_list_row(expense_data.list, "No expenses planned for this period.")

        root.append(this.ui.label("Income Plan", "title-3"))
        root.append(income_data.scroll)
        root.append(this.ui.label("Expense Plan", "title-3"))
        root.append(expense_data.scroll)

        local actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
        actions.append(this.ui.plain_button("Add Expense", function() {
            this.show_budget_envelope_chooser("expense", null, refresh_budget)
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Add Income", function() {
            this.show_budget_envelope_chooser("income", null, refresh_budget)
        }.bindenv(this)))
        actions.append(this.ui.plain_button("Clear Budget", function() {
            this.confirm_action(
                "Clear Budget",
                "Remove every budget row for the current view?",
                function() {
                    this.document.budgets = []
                    this.persist_document("Cleared the current budget.")
                    this.show_budget()
                }.bindenv(this),
                "Clear Budget")
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
            }
            this.persist_document("Copied the budget rows.")
            this.show_budget()
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

        if (envelope.type != "income" && envelope.type != "expense")
            envelope.type = "expense"

        local linked_envelope = this.document.find_envelope(envelope.type, envelope.folder_id, envelope.envelope_id)
        if (linked_envelope != null) envelope.name = linked_envelope.name

        local name_label = this.ui.label(this.document.budget_name(envelope))
        name_label.set_hexpand(true)
        if (linked_envelope == null) name_label.add_css_class("dough-danger")
        box.append(name_label)

        local type_values = ["expense", "income"]
        local type_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Expense", "Income"]), null)
        type_dropdown.set_selected(this.index_for_value(type_values, envelope.type, 0))
        type_dropdown.set_tooltip_text("Choose whether this budget row is income or expense.")
        box.append(type_dropdown)

        local envelope_opts = this.budget_envelope_options(envelope.type, envelope)
        local envelope_dropdown = Gtk.DropDown.new(Gtk.StringList.new(envelope_opts.labels), null)
        envelope_dropdown.set_hexpand(true)
        envelope_dropdown.set_selected(this.index_for_value(
            envelope_opts.paths,
            this.envelope_path(envelope.folder_id, envelope.envelope_id),
            0))
        envelope_dropdown.set_tooltip_text("Choose the catalog envelope for this budget row.")
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
            name_label.set_text(linked.name)
            name_label.remove_css_class("dough-danger")
            this.persist_document()
            if (refresh_budget != null) refresh_budget()
        }.bindenv(this)

        local refresh_envelope_dropdown = function(preferred_path = null) {
            local selected_type = this.dropdown_value(type_values, type_dropdown, envelope.type)
            envelope_opts = selected_type == envelope.type ?
                this.budget_envelope_options(selected_type, envelope) :
                this.envelope_options(selected_type)
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
        allocation_entry.set_tooltip_text("Amount allocated to this envelope for the current period.")
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
            this.confirm_action(
                "Remove Budget Row",
                "Remove " + this.document.budget_name(envelope) + " from this budget?",
                function() {
                    this.remove_array_item_by_id(this.document.budgets, envelope.id)
                    list.remove(row)
                    this.persist_document("Removed budget row.")
                    if (refresh_budget != null) refresh_budget()
                }.bindenv(this),
                "Remove Row")
        }.bindenv(this)))

        row.set_child(box)
        list.append(row)
        return name_label
    }

    function show_budget_envelope_chooser(type, budget_list, refresh_budget = null) {
        local root = this.module_window(
            type == "income" ? "Choose Income Envelope" : "Choose Expense Envelope",
            "Add an existing envelope to the current budget period.",
            "envelope.png")

        local list_data = this.ui.scrolled_list()
        local chooser_win = null
        local visible_count = 0

        foreach (folder in this.document.folders_for_type(type)) {
            local folder_added = false
            foreach (envelope in folder.envelopes) {
                if (folder.hidden || envelope.hidden) continue
                if (!folder_added) {
                    this.ui.add_row(list_data.list, folder.name, null)
                    folder_added = true
                }
                visible_count = visible_count + 1
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
                    if (budget_list != null) this.add_budget_editor_row(budget_list, budget, refresh_budget)
                    this.persist_document("Added existing envelope to budget.")
                    if (refresh_budget != null) refresh_budget()
                    if (chooser_win != null) chooser_win.close()
                    if (budget_list == null) this.show_budget()
                }.bindenv(this)))

                row.set_child(box)
                list_data.list.append(row)
            }
        }

        if (visible_count == 0) {
            this.add_empty_list_row(
                list_data.list,
                type == "income" ?
                    "No income envelopes yet. Create income envelopes in the envelope catalog first." :
                    "No expense envelopes yet. Create expense envelopes in the envelope catalog first.")
            local empty_actions = Gtk.Box.new(Gtk.Orientation.horizontal, 8)
            empty_actions.append(this.ui.plain_button("Open Envelopes", function() {
                if (chooser_win != null) chooser_win.close()
                this.show_envelopes()
            }.bindenv(this)))
            root.append(empty_actions)
        }

        root.append(list_data.scroll)
        chooser_win = this.show_overlay(type == "income" ? "Choose Income Envelope" : "Choose Expense Envelope", root, 680, 440)
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
            this.populate_envelope_catalog(list, type)
            this.persist_document("Added envelope.")
        }.bindenv(this)))

        box.append(this.ui.plain_button("Delete Folder", function() {
            this.confirm_action(
                "Delete Folder",
                "Delete " + folder.name + " and all related budget rows, transactions, and import rules?",
                function() {
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
                }.bindenv(this),
                "Delete Folder")
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
            this.confirm_action(
                "Delete Envelope",
                "Delete " + envelope.name + " and all related budget rows, transactions, and import rules?",
                function() {
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
                }.bindenv(this),
                "Delete Envelope")
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
        mode_entry.set_tooltip_text("Chart mode label used for this graph view.")
        local start_entry = Gtk.Entry.new()
        start_entry.set_placeholder_text("Start date")
        start_entry.set_text(this.current_period_start_iso())
        start_entry.set_tooltip_text("Graph start date in YYYY-MM-DD format.")
        local end_entry = Gtk.Entry.new()
        end_entry.set_placeholder_text("End date")
        end_entry.set_text(this.current_period_end_iso())
        end_entry.set_tooltip_text("Graph end date in YYYY-MM-DD format.")
        local export_entry = Gtk.Entry.new()
        export_entry.set_hexpand(true)
        export_entry.set_placeholder_text("PNG path")
        export_entry.set_text(this.default_export_path(title.find("Pie") == null ? "dough-line-graph.png" : "dough-pie-chart.png"))
        export_entry.set_tooltip_text("Destination path for exported PNG chart.")
        controls.append(mode_entry)
        controls.append(this.date_picker(start_entry))
        controls.append(this.date_picker(end_entry))
        controls.append(export_entry)
        controls.append(this.ui.plain_button("Export PNG", function() {
            this.export_graph_png(export_entry.get_text(), title.find("Pie") != null)
        }.bindenv(this), "Export this chart, including its legend, as a PNG."))
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

    function short_legend_text(text, max_chars = 28) {
        if (text == null) return ""
        if (text.len() <= max_chars) return text
        if (max_chars <= 3) return text.slice(0, max_chars)
        return text.slice(0, max_chars - 3) + "..."
    }

    function draw_legend_item(cr, x, y, color, text) {
        cr.set_source_rgba(color[0], color[1], color[2], 0.88)
        cr.rectangle(x, y, 12, 12)
        cr.fill()

        cr.set_source_rgb(0.16, 0.20, 0.22)
        cr.select_font_face("Sans", 0, 0)
        cr.set_font_size(12)
        cr.move_to(x + 18, y + 11)
        cr.show_text(this.short_legend_text(text))
    }

    function budget_usage_color(spent, budgeted) {
        if (budgeted > 0.0 && spent > budgeted) return [0.74, 0.16, 0.15]
        if (budgeted > 0.0 && spent / budgeted > 0.85) return [0.76, 0.45, 0.12]
        return [0.15, 0.45, 0.55]
    }

    function draw_graph(cr, width, height) {
        cr.set_source_rgb(0.96, 0.96, 0.94)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        local legend_width = width > 520 ? 190.0 : 0.0
        local plot_left = 40.0
        local plot_right = width - 30.0 - legend_width
        if (plot_right < plot_left + 160.0) plot_right = width - 30.0
        local plot_bottom = height - 64.0
        local plot_top = 36.0
        local plot_height = plot_bottom - plot_top

        cr.set_source_rgb(0.16, 0.20, 0.22)
        cr.set_line_width(2)
        cr.move_to(plot_left, plot_bottom)
        cr.line_to(plot_right, plot_bottom)
        cr.move_to(plot_left, plot_top)
        cr.line_to(plot_left, plot_bottom)
        cr.stroke()

        local count = this.document.budgets.len()
        local step = count == 0 ? 78.0 : (plot_right - plot_left - 28.0) / count
        if (step > 78.0) step = 78.0
        if (step < 16.0) step = 16.0
        local bar_width = step - 12.0
        if (bar_width < 6.0) bar_width = 6.0
        local label_chars = (step / 6.0).tointeger()
        if (label_chars < 3) label_chars = 3
        if (label_chars > 12) label_chars = 12

        local x = plot_left + 28.0
        foreach (item in this.document.budgets) {
            local spent = this.document.budget_spent(item)
            local bar_height = item.budgeted == 0.0 ? 4.0 : (spent / item.budgeted) * plot_height
            if (bar_height > plot_height) bar_height = plot_height
            local c = this.budget_usage_color(spent, item.budgeted)
            cr.set_source_rgba(c[0], c[1], c[2], 0.78)
            cr.rectangle(x, plot_bottom - bar_height, bar_width, bar_height)
            cr.fill()

            cr.set_source_rgb(0.16, 0.20, 0.22)
            cr.select_font_face("Sans", 0, 0)
            cr.set_font_size(11)
            cr.move_to(x, plot_bottom + 18.0)
            cr.show_text(this.short_legend_text(this.document.budget_name(item), label_chars))

            x = x + step
            if (x > plot_right - bar_width) break
        }

        if (legend_width > 0.0) {
            local legend_x = width - legend_width + 12.0
            local legend_y = 42.0
            cr.set_source_rgb(0.16, 0.20, 0.22)
            cr.select_font_face("Sans", 0, 1)
            cr.set_font_size(13)
            cr.move_to(legend_x, legend_y - 12.0)
            cr.show_text("Legend")
            this.draw_legend_item(cr, legend_x, legend_y, [0.15, 0.45, 0.55], "Within allocation")
            this.draw_legend_item(cr, legend_x, legend_y + 22.0, [0.76, 0.45, 0.12], "Near allocation")
            this.draw_legend_item(cr, legend_x, legend_y + 44.0, [0.74, 0.16, 0.15], "Over allocation")
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

        local slices = []
        local color_index = 0
        foreach (item in this.document.budgets) {
            if (item.type != "expense") continue
            local value = this.document.budget_spent(item)
            if (value <= 0.0) value = item.budgeted
            if (value <= 0.0) continue
            slices.push({
                item = item,
                value = value,
                color = colors[color_index % colors.len()]
            })
            color_index = color_index + 1
        }
        if (slices.len() == 0) return

        local legend_width = width > 520 ? 220.0 : 0.0
        local chart_width = width - legend_width
        local cx = chart_width / 2.0
        local cy = height / 2.0
        local radius = (chart_width < height ? chart_width : height) / 3.0
        local angle = -1.57079632679

        foreach (slice in slices) {
            local next_angle = angle + ((slice.value / total) * 6.28318530718)
            local c = slice.color
            cr.set_source_rgba(c[0], c[1], c[2], 0.88)
            cr.move_to(cx, cy)
            cr.arc(cx, cy, radius, angle, next_angle)
            cr.close_path()
            cr.fill()
            angle = next_angle
        }

        if (legend_width > 0.0) {
            local legend_x = width - legend_width + 12.0
            local legend_y = 42.0
            cr.set_source_rgb(0.16, 0.20, 0.22)
            cr.select_font_face("Sans", 0, 1)
            cr.set_font_size(13)
            cr.move_to(legend_x, legend_y - 12.0)
            cr.show_text("Legend")

            local max_rows = ((height - legend_y - 12.0) / 22.0).tointeger()
            if (max_rows < 1) max_rows = 1
            local rows = slices.len() > max_rows ? max_rows : slices.len()
            for (local i = 0; i < rows; i = i + 1) {
                local slice = slices[i]
                local label = this.document.budget_name(slice.item) + " " + this.money(slice.value)
                this.draw_legend_item(cr, legend_x, legend_y + (i * 22.0), slice.color, label)
            }
            if (slices.len() > rows) {
                cr.set_source_rgb(0.16, 0.20, 0.22)
                cr.select_font_face("Sans", 0, 0)
                cr.set_font_size(12)
                cr.move_to(legend_x, legend_y + (rows * 22.0) + 11.0)
                cr.show_text("+" + (slices.len() - rows) + " more")
            }
        }
    }

    function show_options() {
        local root = this.module_window(
            "Options",
            "Dough document metadata and display settings.",
            "interface.png")

        local title_entry = Gtk.Entry.new()
        title_entry.set_text(this.document.title)
        title_entry.set_tooltip_text("Budget document title.")
        local currency_entry = Gtk.Entry.new()
        currency_entry.set_text(this.document.currency)
        currency_entry.set_tooltip_text("Currency symbol shown next to money amounts.")
        local reserve_entry = Gtk.Entry.new()
        reserve_entry.set_text(this.amount_text(this.document.reserve_amount))
        reserve_entry.set_tooltip_text("Amount set aside before assigning money to expense envelopes.")
        local reserve_check = Gtk.CheckButton.new_with_label("Reserve enabled")
        reserve_check.set_active(this.document.reserve_enabled)
        reserve_check.set_tooltip_text("Enable or disable the reserve amount in budget calculations.")
        local start_date_entry = Gtk.Entry.new()
        start_date_entry.set_text(this.normalized_date_text(this.document.start_date, this.document.start_date))
        start_date_entry.set_tooltip_text("Budget period start date in YYYY-MM-DD format.")
        local period_values = ["weekly", "fortnightly", "monthly"]
        local period_dropdown = Gtk.DropDown.new(Gtk.StringList.new(["Weekly", "Fortnightly", "Monthly"]), null)
        period_dropdown.set_selected(this.index_for_value(period_values, this.document.period_length, 2))
        period_dropdown.set_tooltip_text("Choose how long each budget period lasts.")

        root.append(this.ui.label("Budget Title"))
        root.append(title_entry)
        root.append(this.ui.label("Currency Symbol"))
        root.append(currency_entry)
        root.append(reserve_check)
        root.append(this.ui.label("Reserve Amount"))
        root.append(reserve_entry)
        root.append(this.ui.label("Start Date"))
        root.append(this.date_picker(start_date_entry))
        root.append(this.ui.label("Period Length"))
        root.append(period_dropdown)
        root.append(this.ui.plain_button("Apply", function() {
            this.document.title = title_entry.get_text()
            this.document.currency = currency_entry.get_text()
            this.document.reserve_enabled = reserve_check.get_active()
            local reserve = this.parse_amount(reserve_entry.get_text())
            if (reserve != null) this.document.reserve_amount = reserve
            local normalized_start_date = this.normalized_date_text(start_date_entry.get_text())
            if (normalized_start_date == null) {
                this.set_status("Choose a valid budget start date.")
                return
            }
            start_date_entry.set_text(normalized_start_date)
            this.document.start_date = normalized_start_date
            this.document.period_length = this.dropdown_value(period_values, period_dropdown, "monthly")
            this.document.regenerate_periods()
            this.persist_document("Options applied and stored in Spinodb.")
        }.bindenv(this), "Save these document options."))

        this.show_window("Options", root, 520, 360)
    }

    function show_about() {
        local dialog = Gtk.AboutDialog.new()
        dialog.set_title("About " + DOUGH_APP_NAME)
        dialog.set_program_name(DOUGH_APP_NAME)
        dialog.set_version(this.version)
        dialog.set_comments("A free personal finance and budgeting application.")
        dialog.set_copyright("Copyright (c) 2026 Camel Software")
        dialog.set_website("https://github.com/supercamel/Dough")
        dialog.set_website_label("github.com/supercamel/Dough")
        dialog.set_license_type(Gtk.License.gpl_3_0)
        dialog.set_modal(true)

        if (this.window != null) dialog.set_transient_for(this.window)

        local icon_path = this.assets.path(DOUGH_ICON_NAME + ".png")
        if (icon_path == null) icon_path = this.assets.path("icon.png")
        if (icon_path != null) {
            try {
                dialog.set_logo(Gdk.Texture.new_from_filename(icon_path))
            } catch (e) {
                dialog.set_logo_icon_name(DOUGH_ICON_NAME)
            }
        } else {
            dialog.set_logo_icon_name(DOUGH_ICON_NAME)
        }

        dialog.present()
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
