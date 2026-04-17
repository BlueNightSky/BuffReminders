local _, BR = ...

-- Namespace scaffold for Options/ modules. Must load before any Options/Modals/* or
-- Options/Tabs/* file so they can populate their slots.
BR.Options = BR.Options or {}
BR.Options.Modals = BR.Options.Modals or {}
BR.Options.Tabs = BR.Options.Tabs or {}

-- Shared layout constants used by modal and tab builders. Keep in sync with the
-- VerticalLayout spacing in Options/Options.lua.
BR.Options.Constants = {
    COMPONENT_GAP = 4, -- standard gap between components
    SECTION_GAP = 8, -- gap before/after section boundaries
    DROPDOWN_EXTRA = 8, -- extra clearance after dropdowns (menu overlay space)
}
