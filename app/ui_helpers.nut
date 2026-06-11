local Gtk = import("Gtk", "4.0")

class WidgetFactory {
    assets = null

    constructor(assets) {
        this.assets = assets
    }

    function label(text, css_class = null) {
        local widget = Gtk.Label.new(text)
        widget.set_xalign(0.0)
        if (css_class != null) widget.add_css_class(css_class)
        return widget
    }

    function padded_box(orientation, spacing, margin = 12) {
        local box = Gtk.Box.new(orientation, spacing)
        box.set_margin_top(margin)
        box.set_margin_bottom(margin)
        box.set_margin_start(margin)
        box.set_margin_end(margin)
        return box
    }

    function image(name, size) {
        local path = this.assets.path(name)
        if (path == null) return Gtk.Label.new("")

        local img = Gtk.Image.new_from_file(path)
        img.set_pixel_size(size)
        return img
    }

    function action_button(text, icon_name, callback) {
        local button = Gtk.Button.new()
        local content = Gtk.Box.new(Gtk.Orientation.horizontal, 6)
        content.append(this.image(icon_name, 20))
        content.append(Gtk.Label.new(text))
        button.set_child(content)
        button.connect("clicked", callback)
        return button
    }

    function plain_button(text, callback) {
        local button = Gtk.Button.new_with_label(text)
        button.connect("clicked", callback)
        return button
    }

    function scrolled_list() {
        local list = Gtk.ListBox.new()
        list.set_selection_mode(Gtk.SelectionMode.none)

        local scroll = Gtk.ScrolledWindow.new()
        scroll.set_vexpand(true)
        scroll.set_child(list)
        return { scroll = scroll, list = list }
    }

    function add_row(list, left, right = null) {
        local row = Gtk.ListBoxRow.new()
        local box = Gtk.Box.new(Gtk.Orientation.horizontal, 12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(10)
        box.set_margin_end(10)

        local lhs = this.label(left)
        lhs.set_hexpand(true)
        box.append(lhs)

        if (right != null) {
            local rhs = Gtk.Label.new(right)
            rhs.set_xalign(1.0)
            box.append(rhs)
        }

        row.set_child(box)
        list.append(row)
    }

    function picture(name, width, height) {
        local path = this.assets.path(name)
        if (path == null) return Gtk.Label.new("")

        local pic = Gtk.Picture.new_for_filename(path)
        pic.set_content_fit(Gtk.ContentFit.contain)
        pic.set_can_shrink(true)
        pic.set_size_request(width, height)
        return pic
    }
}

return {
    WidgetFactory = WidgetFactory
}
