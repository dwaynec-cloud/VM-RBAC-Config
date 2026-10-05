# VM & RBAC Configuration (Project 1 of 6)

Hands-on Azure lab built for AZ-104 (Microsoft Azure Administrator) preparation. It covers Azure infrastructure and security basics: deploying a virtual machine, securing it with a custom least-privilege RBAC role, enforcing tagging with Azure Policy, enabling Encryption at Host, and setting up cost monitoring with budget alerts. The VM, its networking, and the tag-policy assignment are defined as Infrastructure-as-Code in Bicep.

> Related repos: [VNet-Storage-Config](https://github.com/waynethedon/VNet-Storage-Config) (Project 2) · [Monitoring-Backup-Config](https://github.com/waynethedon/Monitoring-Backup-Config) (Project 3) · [Entra-Identity-Config](https://github.com/waynethedon/Entra-Identity-Config) (Project 4) · [AppService-Config](https://github.com/waynethedon/AppService-Config) (Project 5) · [Storage-Recovery-Config](https://github.com/waynethedon/Storage-Recovery-Config) (Project 6)

> **Status:** the lab environment was torn down in October 2026 when the Azure free trial ended. This repo is kept as documentation of the build.

---

## Architecture

- **Resource Group**: `rg-vmrbac-project` (North Central US)
- **Virtual Network**: `vnet-vmrbac-project` with a dedicated subnet for the VM
- **Network Security Group**: inbound SSH allowed from a single known IP address; all other inbound internet traffic denied by default
- **Virtual Machine**: Ubuntu Server 24.04 LTS, SSH key authentication only (no password authentication)
- **Custom RBAC Role**: "VM Operator - No Delete", scoped to this one VM. It grants read, start, restart, deallocate, and power-off. Delete and configuration changes aren't included, and Azure RBAC denies any action a role doesn't grant
- **Azure Policy**: Deny-effect policy requiring a `projects` tag on any new resource in the resource group
- **Encryption at Host**: enabled on the VM (chosen over Azure Disk Encryption; see Key decisions)
- **Cost Budget**: $5/month scoped to the resource group, with email alerts at 80% and 100%
- **Infrastructure as Code**: `main.bicep` defines the NSG, VNet/subnet, public IP, NIC, VM, and the tag-policy assignment. The custom role, Encryption at Host setting, and budget were configured through the Portal and CLI

<img width="653" height="535" alt="Architecture diagram for rg-vmrbac-project" src="https://github.com/user-attachments/assets/e1b9e905-700d-4044-96f0-e5abb166e1ab" />

## Key decisions

**Encryption at Host instead of Azure Disk Encryption (ADE).** The original plan was ADE, which appears in AZ-104 study material. While setting up its Key Vault prerequisite, I found that Microsoft has scheduled ADE for retirement in September 2028 and recommends Encryption at Host instead. Both options encrypt the temp disk, which plain server-side encryption doesn't. I chose Encryption at Host because:
- it's Microsoft's recommended replacement, so it won't need migrating later
- it's a single VM-level setting with no Key Vault dependency
- encryption happens on the Azure host, so it uses none of the VM's CPU, while ADE encrypts inside the guest OS (dm-crypt on Linux)

The Key Vault built for ADE was kept for possible later use.

**RBAC role scoped to the VM, not the resource group.** The role's `assignableScopes` points to the VM's resource ID, matching the requirement to limit access to that one VM. The tradeoff is fragility: deleting and recreating the VM (which happened once during testing) orphaned the role definition, because a role scoped to a resource is tied to that resource's exact ID. A role scoped to the resource group would have survived, but with broader scope.

**Hand-written Bicep instead of Azure Verified Modules (AVM).** Microsoft recommends AVM modules over writing resource definitions from scratch. I wrote this template by hand on purpose, to understand what's inside VM, NIC, and NSG definitions before relying on an abstraction that hides them. A production version would likely use AVM modules.

## Challenges & troubleshooting

**Two different VM deployment errors across five regions.** Small burstable VM sizes failed in Central US, East US, East US 2, and Canada East before succeeding in North Central US. Two different errors were involved:
- `NotAvailableForSubscription` means the VM size is restricted for this subscription in that region. It's an offer or subscription restriction, common on free trials.
- `AllocationFailed` means the region didn't have physical capacity for the request at that moment.

Neither is the same as quota, which is how many vCPUs the subscription is allowed to use. The Quotas blade showed quota wasn't the blocker.

**Stuck deployment from an immutable property.** A failed VM deployment left a resource that blocked the redeploy with `PropertyChangeNotAllowed` on the SSH key, since Azure doesn't allow changing the SSH key of an existing VM resource. Fixed by deleting only the failed VM and its orphaned OS disk, not the whole resource group, then redeploying against the existing networking resources.

**Accidental VM deletion during RBAC testing.** While testing that the custom role blocked deletes, I ran the delete from my admin session instead of the test user's and deleted the VM. After rebuilding it, the custom role had also been orphaned, because a role scoped to a specific resource ID can't be listed once that resource is gone. I recreated the role against the new VM's resource ID and re-verified both directions of access.

**Budget scope confusion.** Creating a budget from the top-level Billing account view only offered billing-account scopes. Budgets for a subscription or resource group have to be created from that subscription's own Cost Management blade.

**A resource-group deployment can't create a subscription-scoped role.** Adding the custom role definition to `main.bicep` as a subscription-scoped module failed (Bicep error BCP134), because a resource-group-scoped deployment can't deploy to a higher scope. The working design is two separate deployments: a subscription-scoped `rbac-role.bicep` deployed with `az deployment sub create`, whose output role ID is passed into `main.bicep` as a parameter. This part isn't finished yet (see Next steps).

## Verification

Every control was tested, not just configured:

- **RBAC:** signed in as the test user and confirmed they could view, start, and stop the VM, but got `Authorization failed` when attempting to delete it
- **Tag policy:** attempted to create a resource without the `projects` tag in the resource group and was denied by the policy before deployment
- **Encryption at Host:** `az vm show --query securityProfile.encryptionAtHost` returned `true`
- **Bicep template:** deployed end to end into a separate, clean resource group and confirmed SSH access to the resulting VM

**Least privilege: the test user is denied when deleting the VM**

<img width="1496" height="835" alt="Test user receiving Authorization failed when deleting the VM" src="https://github.com/user-attachments/assets/683ad0f3-13d9-4d05-a399-ece73254bd9d" />

**Tag policy enforcement: resource without the required tag denied**

<img width="685" height="421" alt="Tag policy denying an untagged resource" src="https://github.com/user-attachments/assets/fd60f5bb-984e-4701-8c2c-fd5277a298fe" />

<img width="1934" height="868" alt="Tag policy denial details" src="https://github.com/user-attachments/assets/7d2963e6-646a-427b-9868-80a06235991d" />

**Encryption at Host: CLI and Portal views**

<img width="552" height="204" alt="az vm show returning encryptionAtHost true" src="https://github.com/user-attachments/assets/f6f69bed-a8dc-4871-b620-d37424e2f1d9" />

<img width="810" height="697" alt="Portal showing Encryption at Host enabled" src="https://github.com/user-attachments/assets/bba7a576-7911-42d4-8525-d119d5096d19" />

## How to deploy

```bash
git clone https://github.com/waynethedon/VM-RBAC-Config.git
cd VM-RBAC-Config
az login
az group create --name <your-resource-group> --location <your-region>
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file main.bicep \
  --parameters sshPublicKey="<your-ssh-public-key>"
```

This deploys the VM, its networking, and the tag-policy assignment. The custom RBAC role, Encryption at Host setting, and cost budget are configured separately through the Portal or CLI.

## Next steps

- Finish `rbac-role.bicep` as a separate subscription-scoped deployment and pass its role ID into `main.bicep` for the role assignment
- Codify the cost budget (`Microsoft.Consumption/budgets`) and the Encryption at Host setting (`securityProfile.encryptionAtHost` on the VM resource)
- Compare this hand-written template with an equivalent built from Azure Verified Modules
