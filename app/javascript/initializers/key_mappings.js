import { application } from "controllers/application"

// Stimulus ships nicknames for named keys and alphanumerics only; "/" needs its own.
application.schema = { ...application.schema, keyMappings: { ...application.schema.keyMappings, slash: "/" } }
