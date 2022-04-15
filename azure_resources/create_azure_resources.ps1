# login to Azure
az login
# TODO - get the subscription ID for use in creating redis in VNET

# Setting to $true will create the resources, otherwise it will 
# just update firewall rules
$create = $false

$resource_group_name = "superset01"
$location = "westus3"
$UNIQUE_NAME = "eisuperset01"
$myIpAddress = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
$DATABASE_DB = "superset"
$POSTGRES_USER = "postgres"
# to get skus:
# az postgres flexible-server list-skus -l $location -o table
$sku_name = "Standard_B2s"
# $vnet = $resource_group_name

$docker_compose_file = "docker-compose-azure.yml"

If ($create){
    # create the resource group - will get created by server create command
    # az group create --name $resource_group_name --location $location

    # create the PostgreSQL server
    # single server
    # az postgres server create --resource-group $resource_group_name --name $UNIQUE_NAME --location $location --admin-user $POSTGRES_USER --sku-name B_Gen5_1

    # flexible server
    az postgres flexible-server create --resource-group $resource_group_name `
                                    --location $location `
                                    --name $UNIQUE_NAME `
                                    --public-access = $myIpAddress `
                                    --sku-name $sku_name `
                                    --admin-user $POSTGRES_USER
                                    # --vnet $vnet `
                                   
    # create the database
    az postgres flexible-server db create --resource-group $resource_group_name `
                                    --server-name $UNIQUE_NAME `
                                    --database-name $DATABASE_DB 

    # create the redis cache
    az redis create --resource-group $resource_group_name `
                                    --location $location `
                                    --name $UNIQUE_NAME `
                                    --sku Basic `
                                    --vm-size C0 # `
                                    # --subnet-id /subscriptions/{subid}/resourceGroups/$resource_group_name/providers/Microsoft.{Network|ClassicNetwork}/virtualNetworks/vnet1/subnets/subnet1
    # VNET - if we use premium skus, then we can put everything in a VNET (I believe)

    # issue - must first find SKU/region that will work - no B1, B2, S1, D1 in westus2
    #         ERROR: This region has quota of 0 instances for your subscription. Try selecting different region or SKU.
    #   had to switch to westus3 region
    #   need to check for all of the resources in desired region, 
    #   then if not available, check adjacent region and make recommendation
    
    # issue - what sku is recommended for the containers needed?
    #   e.g. for 1 user use xx (better yet if this can be in terms of ACU!)
    #        for 5 users use yy
    #        for 20 users use zz

    # create the app service plan
    az appservice plan create --resource-group $resource_group_name `
                                    --location $location `
                                    --name $UNIQUE_NAME `
                                    --is-linux `
                                    --sku B2 #(Basic Medium - 200 ACU, 3.5GB, $25/mo)
    
    # issue - why --sku instead of --sku-name?

    # create the webapp to host the containers
    az webapp create --resource-group $resource_group_name `
                                    --plan $UNIQUE_NAME `
                                    --name $UNIQUE_NAME `
                                    --multicontainer-config-type compose `
                                    --multicontainer-config-file $docker_compose_file

    # create the storage account for volume mapping
    # create storage account
    az storage account create --resource-group $resource_group_name `
                                    --location $location `
                                    --name $UNIQUE_NAME

    # get the account-key
    $storage_account_key = (az storage account keys list --account-name $UNIQUE_NAME | ConvertFrom-Json)[0].value

    #region superset volume
    $volume_name = "superset"
    # create the container for the volume
    az storage container create --account-name $UNIQUE_NAME `
                                    --name $volume_name

    # upload files to the container
    az storage blob upload-batch --account-name $UNIQUE_NAME `
                                --destination $volume_name  `
                                --account-key $storage_account_key `
                                --source  . `
                                --pattern superset_config.py

    # mount the container
    az webapp config storage-account add --resource-group $resource_group_name `
                                --name $UNIQUE_NAME `
                                --custom-id $volume_name `
                                --storage-type AzureBlob `
                                --share-name $volume_name `
                                --account-name $UNIQUE_NAME `
                                --access-key $storage_account_key `
                                --mount-path /etc/superset
    #endregion superset volume
    
    #region docker volume
    $volume_name = "docker"
    # create the container for the volume
    az storage container create --account-name $UNIQUE_NAME `
                                    --name $volume_name

    # upload files to the container
    az storage blob upload-batch --account-name $UNIQUE_NAME `
                                --destination $volume_name  `
                                --account-key $storage_account_key `
                                --source  .\docker `
                                --pattern *

    # mount the container
    az webapp config storage-account add --resource-group $resource_group_name `
                                --name $UNIQUE_NAME `
                                --custom-id $volume_name `
                                --storage-type AzureBlob `
                                --share-name $volume_name `
                                --account-name $UNIQUE_NAME `
                                --access-key $storage_account_key `
                                --mount-path /app/docker
    #endregion docker volume

    #region supersethome volume
    $volume_name = "supersethome"
    # create the container for the volume
    az storage container create --account-name $UNIQUE_NAME `
                                    --name $volume_name

    # upload files to the container
    # az storage blob upload-batch --account-name $UNIQUE_NAME `
    #                             --destination $volume_name  `
    #                             --account-key $storage_account_key `
    #                             --source  . `
    #                             --pattern superset_config.py

    # mount the container
    az webapp config storage-account add --resource-group $resource_group_name `
                                --name $UNIQUE_NAME `
                                --custom-id $volume_name `
                                --storage-type AzureBlob `
                                --share-name $volume_name `
                                --account-name $UNIQUE_NAME `
                                --access-key $storage_account_key `
                                --mount-path /app/superset_home
    #endregion supersethome volume

    # update webapp to pick up the storage
    az webapp config container set --resource-group $resource_group_name `
                                --name $UNIQUE_NAME `
                                --multicontainer-config-type compose `
                                --multicontainer-config-file "docker-compose-azure.yml"

                            }

# update postgres firewall rule
az postgres flexible-server firewall-rule update `
                                    --resource-group $resource_group_name `
                                    --name $UNIQUE_NAME `
                                    --start-ip-address $myIpAddress `
                                    --end-ip-address $myIpAddress `
                                    --rule-name AllowLocalClient1


# update redis firewall rule
az redis firewall-rules update `
                --resource-group $resource_group_name `
                --name $UNIQUE_NAME `
                --start-ip $myIpAddress `
                --end-ip $myIpAddress `
                --rule-name AllowLocalClient1
# issue - why firewall-rule(s) instead of firewall-rule like pg?
# issue - why start-ip vs start-ip-address?




# create the firewall 
#    rule for the database - not needed if use --public-access [IPaddress]
# az postgres server firewall-rule create --resource-group $resource_group_name --server-name $UNIQUE_NAME --start-ip-address=0.0.0.0 --end-ip-address=0.0.0.0 --name AllowAllAzureIPs
# single server
# az postgres server firewall-rule create --resource-group $resource_group_name --server-name $UNIQUE_NAME --start-ip-address=$myIpAddress --end-ip-address=$myIpAddress --name AllowLocalClient1
# flexible server
# az postgres flexible-server firewall-rule create --resource-group $resource_group_name --name $UNIQUE_NAME --start-ip-address=$myIpAddress --end-ip-address=$myIpAddress --rule-name AllowLocalClient1


# need pgadmin
# winget install PostgreSQL.pgAdmin
# psql -h "charrissuperset.postgres.database.azure.com" -U admin charris
# could use install location without restarting CLI, but this is super fragile:
#   & "~\appdata\local\programs\pgAdmin 4\v6\runtime\psql.exe"
# Push-Location "~\appdata\local\programs\pgAdmin 4\v6\runtime"
# .\psql.exe -h "$UNIQUE_NAME.postgres.database.azure.com" -U "$POSTGRES_USER@$UNIQUE_NAME" postgres
# > CREATE DATABASE $DATABASE_DB;
# > exit
# Pop-Location
