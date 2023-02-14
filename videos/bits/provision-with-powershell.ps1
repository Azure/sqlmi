#This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. 
#THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
#INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We grant You a nonexclusive, 
#royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: 
#(i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to 
#include a valid copyright notice on Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, 
#and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code.

import-module AZ
Login-AzAccount
Get-AZSubscription
Set-AzContext "EnterYourSubscriptionIDHere"


# Create Azure SQL Managed Instance
$NSnetworkModels = "Microsoft.Azure.Commands.Network.Models"
$NScollections = "System.Collections.Generic"
# The SubscriptionId in which to create these objects
$SubscriptionId = 'd2cb2c6b-ec9e-44c1-ba26-88a4209f9680'
# Set the resource group name and location for your managed instance
$resourceGroupName = "myResourceGroup-$(Get-Random)"
$location = "westus3"
# Set the networking values for your managed instance
$vNetName = "myVnet-$(Get-Random)"
$vNetAddressPrefix = "20.0.0.0/16"
$miSubnetName = "myMISubnet-$(Get-Random)"
$miSubnetAddressPrefix = "20.0.0.0/24"
#Set the managed instance name for the new managed instance
$instanceName = "myMIName-$(Get-Random)"
# Set the admin login and password for your managed instance
$miAdminSqlLogin = "SqlAdmin"
$miAdminSqlPassword = "ChangeYourAdminPassword1"
# Set the managed instance service tier, compute level, and license mode
$edition = "General Purpose"
$vCores = 4
$maxStorage = 128
$computeGeneration = "Gen5"
$license = "LicenseIncluded" #"BasePrice" or LicenseIncluded if you have don't have SQL Server license that can be used for AHB discount

# Create a resource group
$resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $location -Tag @{Owner="SQLDB-Samples"}

# Configure virtual network, subnets, network security group, and routing table
$virtualNetwork = New-AzVirtualNetwork `
                      -ResourceGroupName $resourceGroupName `
                      -Location $location `
                      -Name $vNetName `
                      -AddressPrefix $vNetAddressPrefix

Add-AzVirtualNetworkSubnetConfig `
    -Name $miSubnetName `
    -VirtualNetwork $virtualNetwork `
    -AddressPrefix $miSubnetAddressPrefix |
Set-AzVirtualNetwork
                  
$scriptUrlBase = 'https://raw.githubusercontent.com/Microsoft/sql-server-samples/master/samples/manage/azure-sql-db-managed-instance/delegate-subnet'

$parameters = @{
    subscriptionId = $SubscriptionId
    resourceGroupName = $resourceGroupName
    virtualNetworkName = $vNetName
    subnetName = $miSubnetName
    }

Invoke-Command -ScriptBlock ([Scriptblock]::Create((iwr ($scriptUrlBase+'/delegateSubnet.ps1?t='+ [DateTime]::Now.Ticks)).Content)) -ArgumentList $parameters

$virtualNetwork = Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $resourceGroupName
$miSubnet = Get-AzVirtualNetworkSubnetConfig -Name $miSubnetName -VirtualNetwork $virtualNetwork
$miSubnetConfigId = $miSubnet.Id

##
# Create credentials
$secpassword = ConvertTo-SecureString $miAdminSqlPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($miAdminSqlLogin, $secpassword)

# Create managed instance
New-AzSqlInstance -Name $instanceName `
                      -ResourceGroupName $resourceGroupName -Location $location -SubnetId $miSubnetConfigId `
                      -AdministratorCredential $credential `
                      -StorageSizeInGB $maxStorage -VCore $vCores -Edition $edition `
                      -ComputeGeneration $computeGeneration -LicenseType $license

# Clean up deployment 
Remove-AzResourceGroup -ResourceGroupName $resourceGroupName
