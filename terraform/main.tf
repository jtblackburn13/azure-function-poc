locals {
  source_root  = "${path.module}/.."
  build_dir    = "${path.module}/build"
  package_path = "${local.build_dir}/function.zip"
  name_prefix  = "${var.project_name}-${var.environment}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name_prefix}"
  location = var.location
}

resource "azurerm_storage_account" "sa" {
  name                     = "st${var.project_name}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "ai" {
  name                = "appi-${local.name_prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
}

resource "azurerm_service_plan" "asp" {
  name                = "asp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "null_resource" "build_handler" {
  triggers = {
    main_go = filesha256("${local.source_root}/main.go")
    go_mod  = filesha256("${local.source_root}/go.mod")
  }

  provisioner "local-exec" {
    working_dir = local.source_root
    command     = "mkdir -p ${abspath(local.build_dir)}/pkg && cp host.json ${abspath(local.build_dir)}/pkg/host.json && mkdir -p ${abspath(local.build_dir)}/pkg/HelloWorld && cp HelloWorld/function.json ${abspath(local.build_dir)}/pkg/HelloWorld/function.json && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ${abspath(local.build_dir)}/pkg/handler ."
    interpreter = ["/bin/sh", "-c"]
    environment = {
      GOFLAGS = "-trimpath"
    }
  }
}

data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${local.build_dir}/pkg"
  output_path = local.package_path

  depends_on = [null_resource.build_handler]
}

resource "azurerm_storage_container" "deploy" {
  name                  = "function-releases"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "package" {
  name                   = "function-${data.archive_file.function_zip.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.sa.name
  storage_container_name = azurerm_storage_container.deploy.name
  type                   = "Block"
  source                 = data.archive_file.function_zip.output_path
  content_md5            = data.archive_file.function_zip.output_md5
}

data "azurerm_storage_account_blob_container_sas" "package" {
  connection_string = azurerm_storage_account.sa.primary_connection_string
  container_name    = azurerm_storage_container.deploy.name
  https_only        = true

  start  = "2026-01-01T00:00:00Z"
  expiry = "2030-01-01T00:00:00Z"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

resource "azurerm_linux_function_app" "fa" {
  name                = "func-${local.name_prefix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  functions_extension_version = "~4"

  site_config {
    application_insights_connection_string = azurerm_application_insights.ai.connection_string
    application_insights_key               = azurerm_application_insights.ai.instrumentation_key

    application_stack {
      use_custom_runtime = true
    }

    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "custom"
    WEBSITE_RUN_FROM_PACKAGE = "https://${azurerm_storage_account.sa.name}.blob.core.windows.net/${azurerm_storage_container.deploy.name}/${azurerm_storage_blob.package.name}${data.azurerm_storage_account_blob_container_sas.package.sas}"
  }
}
