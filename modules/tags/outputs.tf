output "tags" {
  description = "Merged mandatory + extra tag map to feed into provider default_tags."
  value       = local.tags
}

output "mandatory_tags" {
  description = "The mandatory tag set only, without extra_tags applied."
  value       = local.mandatory_tags
}

output "name_prefix" {
  description = "Canonical resource name prefix: <project>-<environment>."
  value       = local.name_prefix
}
