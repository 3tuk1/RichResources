data:extend({
  {
    type = "double-setting",
    name = "rich-resources-multiplier",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0.001,
    maximum_value = 1000000,
    order = "a-1"
  },
   {
     type = "bool-setting",
     name = "richresources-apply-to-existing-ores",
     setting_type = "runtime-global",
     default_value = false,
     order = "a[richresources]-b[apply-to-existing-ores]"
   },
   {
     type = "bool-setting",
     name = "richresources-reset-processed-list",
     setting_type = "runtime-global",
     default_value = false,
     order = "a[richresources]-c[reset-processed-list]"
   },
   {
     type = "int-setting",
     name = "rich-resources-infinite-min-base",
     setting_type = "runtime-global",
     default_value = 300000,
     minimum_value = 1,
     maximum_value = 1000000000,
     order = "a[richresources]-d[infinite-min-base]"
   },
   {
     type = "double-setting",
     name = "rich-resources-maintenance-multiplier",
     setting_type = "runtime-global",
     default_value = 1.0,
     minimum_value = 0.001,
     maximum_value = 1000,
     order = "a[richresources]-e[maintenance-multiplier]"
   },
   {
     type = "bool-setting",
     name = "richresources-apply-maintenance",
     setting_type = "runtime-global",
     default_value = false,
     order = "a[richresources]-f[apply-maintenanc"
   },
   {
     type = "int-setting",
     name = "rich-resources-infinite-min-base",
     setting_type = "runtime-global",
     default_value = 30000,
     minimum_value = 1,
     maximum_value = 1000000000,
     order = "a[richresources]-d[infinite-min-base]"
   },
   {
     type = "double-setting",
     name = "rich-resources-maintenance-multiplier",
     setting_type = "runtime-global",
     default_value = 1.0,
     minimum_value = 0.001,
     maximum_value = 1000,
     order = "a[richresources]-e[maintenance-multiplier]"
   },
   {
     type = "bool-setting",
     name = "richresources-apply-maintenance",
     setting_type = "runtime-global",
     default_value = false,
     order = "a[richresources]-f[apply-maintenance]"
   }
})