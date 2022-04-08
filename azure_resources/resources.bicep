param basename string
param location string
param principalId string = ''
@description('Name that will be used to build associated artifacts')
param appName string = uniqueString(resourceGroup().id)

resource web 'Microsoft.Web/sites@2021-01-15' = {
  name: '${basename}web'
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: farm.id
    siteConfig: {
      linuxFxVersion: 'NODE|14-lts'
      alwaysOn: true
      ftpsState: 'FtpsOnly'
      appCommandLine: 'pm2 serve /home/site/wwwroot --no-daemon --spa'
    }
    httpsOnly: true
  }

  resource webappappsettings 'config' = {
    name: 'appsettings'
    properties: {
      'SCM_DO_BUILD_DURING_DEPLOYMENT': 'false'
      'APPINSIGHTS_INSTRUMENTATIONKEY': insights.outputs.APPINSIGHTS_INSTRUMENTATIONKEY
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }
}

resource api 'Microsoft.Web/sites@2021-01-15' = {
  name: '${basename}api'
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: farm.id
    siteConfig: {
      alwaysOn: true
      linuxFxVersion: 'PYTHON|3.8'
      ftpsState: 'FtpsOnly'
      appCommandLine: 'gunicorn --workers 4 --threads 2 --timeout 60 --access-logfile "-" --error-logfile "-" --bind=0.0.0.0:8000 -k uvicorn.workers.UvicornWorker todo.app:app'
    }
    httpsOnly: true
  }

  identity: {
    type: 'SystemAssigned'
  }

  resource appsettings 'config' = {
    name: 'appsettings'
    properties: {
      'COSMOS_CONNECTION_STRING_KEY': 'COSMOS-CONNECTION-STRING'
      'COSMOS_DATABASE_NAME': cosmos::database.name
      'SCM_DO_BUILD_DURING_DEPLOYMENT': 'true'
      'AZURE_KEY_VAULT_ENDPOINT': keyvault.properties.vaultUri
      'APPINSIGHTS_INSTRUMENTATIONKEY': insights.outputs.APPINSIGHTS_INSTRUMENTATIONKEY
    }
  }

  resource logs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
  }
}

resource farm 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: '${basename}farm'
  location: location
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

resource keyvault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${basename}kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        objectId: principalId
        permissions: {
          secrets: [
            'all'
          ]
        }
        tenantId: subscription().tenantId
      }
      {
        objectId: api.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
  }

  resource cosmosconnectionstring 'secrets' = {
    name: 'COSMOS-CONNECTION-STRING'
    properties: {
      value: cosmos.listConnectionStrings().connectionStrings[0].connectionString
    }
  }
}

module insights './appinsights.bicep' = {
  name: '${basename}airesources'
  params: {
    basename: toLower(basename)
    location: location
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2021-04-15' = {
  name: '${basename}cosmos'
  kind: 'MongoDB'
  location: location
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    apiProperties: {
      serverVersion: '4.0'
    }
  }

  resource database 'mongodbDatabases' = {
    name: 'Todo'
    properties: {
      resource: {
        id: 'Todo'
      }
    }

    resource list 'collections' = {
      name: 'TodoList'
      properties: {
        resource: {
          id: 'TodoList'
          shardKey: {
            name: 'Hash'
          }
          indexes: [
            {
              key: {
                keys: [
                  '_id'
                ]
              }
            }
          ]
        }
      }
    }

    resource item 'collections' = {
      name: 'TodoItem'
      properties: {
        resource: {
          id: 'TodoItem'
          shardKey: {
            name: 'Hash'
          }
          indexes: [
            {
              key: {
                keys: [
                  '_id'
                ]
              }
            }
          ]
        }
      }
    }
  }
}

output COSMOS_CONNECTION_STRING_KEY string = 'COSMOS-CONNECTION-STRING'
output COSMOS_DATABASE_NAME string = cosmos::database.name
output AZURE_KEY_VAULT_ENDPOINT string = keyvault.properties.vaultUri
output APPINSIGHTS_NAME string = insights.outputs.APPINSIGHTS_NAME
output APPINSIGHTS_INSTRUMENTATIONKEY string = insights.outputs.APPINSIGHTS_INSTRUMENTATIONKEY
output APPINSIGHTS_DASHBOARD_NAME string = insights.outputs.APPINSIGHTS_DASHBOARD_NAME
output API_URI string = 'https://${api.properties.defaultHostName}'
