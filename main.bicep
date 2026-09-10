@description('The name of the virtual machine.')
param vmName string = 'vm1'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Admin username for the virtual machine.')
param adminUsername string = 'azureuser'

@description('The SSH public key for authentication.')
param sshPublicKey string

@description('VM size')
param vmSize string = 'Standard_B2ats_v2'


var vnetName = 'vnet-vmrbac-project'
var subnetName = 'subnet-vm-resources'
var nsgName = 'nsg-vmrbac-project'
var publicIPName = '${vmName}-ip'
var nicName = '${vmName}-nic'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-MyIP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '64.217.151.163/32'
          destinationAddressPrefix: '*'
      }
    }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.16.0.0/24'
      ]
    }
    subnets: [
        {
            name: subnetName
            properties: {
                addressPrefix: '172.16.0.0/24'
                networkSecurityGroup: {
                    id: nsg.id
                }
            }
        }
    ]
  }
}   

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIPName
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          
          }
        }
      
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
        }
        osDisk: {
            createOption: 'FromImage'
            deleteOption: 'Delete'
            managedDisk: {
                storageAccountType: 'Premium_LRS'
            }
        }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }

        ]
    }      
} 
    tags: {
        project: 'vmrbac-lab'

    }
}


output vmPublicIP string = publicIP.properties.ipAddress
output sshCommand string = 'ssh -i <path-to-key> ${adminUsername}@${publicIP.properties.ipAddress}'
