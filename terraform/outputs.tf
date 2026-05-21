output "function_app_name" {
  description = "Name of the deployed Function App."
  value       = azurerm_linux_function_app.fa.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App."
  value       = azurerm_linux_function_app.fa.default_hostname
}

output "hello_world_url" {
  description = "Invocation URL for the HelloWorld function."
  value       = "https://${azurerm_linux_function_app.fa.default_hostname}/api/HelloWorld"
}

output "resource_group_name" {
  description = "Resource group containing all resources."
  value       = azurerm_resource_group.rg.name
}
