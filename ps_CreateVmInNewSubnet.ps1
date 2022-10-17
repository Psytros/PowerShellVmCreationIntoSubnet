# Variables
$location = "switzerland north"
$resourceGroupName = "TestMyTerraformGroup"

$vmName = "VmPowerShell01"

$vmUsername = "demousr"
$vmPassword = "Password123!" | ConvertTo-SecureString -Force -AsPlainText

$vmSize = "Standard_B2ms"
$vmImage = "*/WindowsServer/Skus/2022-datacenter-azure-edition"

$vmOsDiskSizeInGB = 127
$vmOsDiskSku = "StandardSSD_LRS"

$vmDataDiskSizeInGB = 16
$vmDataDiskSku = "StandardSSD_LRS"

$vnetName = "vNetTerraformA"
$subnetName = "SubnetPS"
$subnetAddressPrefix = "10.230.2.0/24"

$nsgName = "$($vmName)-Nsg"
$nicName = "$($vmName)-Nic"
$ipConfigName = "ipconfig1"
$pipName = "$($vmName)-Pip"


# Get informations about the vnet
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName

## Create new network resources
Write-Host "Prepare network for VM"

# Create a new subnet
Write-Host "Create new Subnet and set it on vnet"
Add-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetAddressPrefix
$vnet | Set-AzVirtualNetwork

#Create new PIP
Write-Host "Crerate new PIP"
$pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $resourceGroupName -Location $location `
         -Sku Basic -AllocationMethod Static

# Create new NSG rule
$nsgRule = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" -Description "Allow RDP" -Priority 300 `
                -SourcePortRange "*" -SourceAddressPrefix "*" `
                -DestinationPortRange "3389" -DestinationAddressPrefix "*" `
                -Direction Inbound -Protocol Tcp -Access Allow

# Create new NSG
Write-Host "Crerate new NSG"
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRule

# Create a new NIC
Write-Host "Create new NIC"
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet
$pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $resourceGroupName

$ipConfig = New-AzNetworkInterfaceIpConfig -Name $ipConfigName -SubnetId $subnet.Id -PublicIpAddressId $pip.Id -Primary

$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName -Location $location `
            -IpConfiguration $ipConfig -NetworkSecurityGroupId $nsg.Id

## Create new Virtual Machine
Write-Host "Prepare new VM - $($vmName)"

# Create credentials
$credentials = New-Object -TypeName pscredential -ArgumentList ($vmUsername, $vmPassword)

# Create new VM config
$vm = New-AzVMConfig -VMName $vmName -VMSize $vmSize | Out-Null

# Add NIC to VM
Add-AzVMNetworkInterface -VM $vm -Id $nic.Id | Out-Null

# Set VM size and type
Set-AzVMOperatingSystem -VM $vm -ComputerName $vmName -Credential $credentials -Windows -ProvisionVMAgent

# Get the VM source image
$vmImageSource = Get-AzVMImageOffer -Location $location -PublisherName "MicrosoftWindowsServer" | Get-AzVMImageSku | `
                  Where-Object -FilterScript {$_.Id -like $vmImage}

# Set VM source image
Set-AzVMSourceImage -VM $vm -PublisherName $vmImageSource.PublisherName -Offer $vmImageSource.Offer -Skus $vmImageSource.Skus `
         -Version "latest" | Out-Null

# Create OS Disk
Write-Host "Create managed VM OS Disk"
$osDiskGuid = ([guid]::NewGuid().Guid).Replace('-', '')
$osDiskName = "$($vmName)-OsDisk_$($osDiskGuid)"

Set-AzVMOSDisk -VM $vm -Name $osDiskName -Windows -CreateOption fromImage -DiskSizeInGB $vmOsDiskSizeInGB -StorageAccountType $vmOsDiskSku | Out-Null

# Create Data Disk
Write-Host "Create managed VM Data Disk"

$dataDiskName = "$($vmName)-DataDisk"

$dataDiskConfig = New-AzDiskConfig -Location $location -SkuName $vmDataDiskSku -DiskSizeGB $vmDataDiskSizeInGB -OsType Windows -CreateOption "Empty"
$dataDisk = New-AzDisk -DiskName $dataDiskName -ResourceGroupName $resourceGroupName -Disk $dataDiskConfig

Add-AzVMDataDisk -VM $vm -Name $dataDiskName -CreateOption Attach -Lun 0 -Caching ReadWrite -ManagedDiskId $dataDisk.Id | Out-Null

# Set Boot Diagnostic to off
Set-AzVMBootDiagnostic -VM $vm -Disable | Out-Null

# Create new VM
Write-Host "Create new VM - $($vmName)"

New-AzVM -VM $vm -ResourceGroupName $resourceGroupName -Location $location

Write-Host "$($vmName) created"
