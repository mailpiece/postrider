pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/turbo/offline", to: "turbo-offline.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/request.js", to: "@rails--request.js" # @0.0.13

pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/helpers", under: "helpers"
pin_all_from "app/javascript/lib", under: "lib"
pin_all_from "app/javascript/initializers", under: "initializers"
