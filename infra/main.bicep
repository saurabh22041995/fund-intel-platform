targetScope = 'resourceGroup'

@minLength(3)
@maxLength(8)
param project string = 'fpi'

@allowed(['dev', 'test', 'prod'])
param env string = 'dev'

param location string = resourceGroup().location

@allowed(['free', 'basic', 'standard'])
param searchSku string = 'basic'

param pgAdminUser string = 'pgadmin'

@secure()
param pgAdminPassword string

@description('Your public IP, to allow local access to PostgreSQL. Leave empty to skip.')
param myIp string = ''

var suffix = take(uniqueString(resourceGroup().id, 'v2'), 6)
var tags = {
  project: project
  env: env
  managedBy: 'bicep'
}

// Blob storage: raw documents land here
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'sto${project}${env}${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource rawContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'raw-documents'
  properties: { publicAccess: 'None' }
}

// Key Vault: secrets, accessed through Azure RBAC
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kvo-${project}-${env}-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Azure AI Search: the RAG index lives here (Weeks 4-5)
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: 'srche-${project}-${env}-${suffix}'
  location: location
  tags: tags
  sku: { name: searchSku }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
  }
}

// Azure OpenAI account (model deployments are added separately, see below)
resource openai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: 'opai-${project}-${env}-${suffix}'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: 'oai-${project}-${env}-${suffix}'
    publicNetworkAccess: 'Enabled'
  }
}

// PostgreSQL Flexible Server
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: 'pgs-${project}-${env}-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: pgAdminUser
    administratorLoginPassword: pgAdminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
  }
}

resource pgDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: pg
  name: 'fpi'
}

resource pgMyIp 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = if (!empty(myIp)) {
  parent: pg
  name: 'allow-my-ip'
  properties: { startIpAddress: myIp, endIpAddress: myIp }
}

output storageAccountName string = storage.name
output keyVaultName string = kv.name
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output openAiEndpoint string = openai.properties.endpoint
output postgresHost string = pg.properties.fullyQualifiedDomainName
