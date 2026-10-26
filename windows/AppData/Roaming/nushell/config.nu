$env.config.show_banner = false
$env.config.edit_mode = "vi"

$env.config.completions.algorithm = "fuzzy"
$env.config.completions.case_sensitive = false
$env.config.completions.quick = true
$env.config.completions.partial = true

$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 100_000
$env.config.history.sync_on_enter = true

$env.config.buffer_editor = "nvim"

# WezTerm: prevent OSC 133 scrolling issue
$env.config.shell_integration.osc133 = false

source aliases.nu
