local App = import("app/application.nut")

local options = {
    smoke = false
}

foreach (arg in vargv) {
    if (arg == "--smoke") options.smoke = true
}

local app = App.DoughApplication(options)
return app.run(0, null)
