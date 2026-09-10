
# VM & RBAC Configuration

This project demonstrates hands-on Azure infrastructure and security configuration: deploying a virtual machine, securing it with a custom least-privilege RBAC role, enforcing tagging governance via Azure Policy, enabling host-based disk encryption, and configuring cost monitoring with budget alerts. The full environment is also defined as reusable Infrastructure-as-Code using Bicep.

## Architecture

- **Resource Group**: `rg-vmrbac-project` (North Central US)
- **Virtual Network**: `vnet-vmrbac-project` with a dedicated subnet for the VM
- **Network Security Group**: inbound SSH restricted to a single known IP address; all other inbound traffic denied by default
- **Virtual Machine**: Ubuntu Server 24.04 LTS, SSH key-based authentication only (no password auth)
- **Custom RBAC Role**: "VM Operator - No Delete" — scoped to this specific VM, grants read/start/restart/deallocate but explicitly excludes delete and configuration-change permissions
- **Azure Policy**: Deny-effect policy requiring a `project` tag on any new resource in the resource group
- **Encryption at Host**: enabled on the VM (chosen over Azure Disk Encryption — see Key Decisions below)
- **Cost Budget**: $5/month scoped to the resource group, with email alerts at 80% and 100% thresholds
- **Infrastructure as Code**: full environment (NSG, VNet/subnet, Public IP, NIC, VM) defined in `main.bicep`

*(Architecture diagram attached)*

<img width="653" height="535" alt="Logical diagram Azure Rg-vmrbac-project " src="https://github.com/user-attachments/assets/e1b9e905-700d-4044-96f0-e5abb166e1ab" />


## Key decisions

**Azure Disk Encryption → Encryption at Host.** The original plan was to use Azure Disk Encryption (ADE), which is an explicit AZ-104 exam objective. While researching the Key Vault prerequisite, I found that Microsoft has scheduled ADE for retirement (September 2028) in favor of Encryption at Host. I built the Key Vault as originally planned, but pivoted the actual encryption implementation to Encryption at Host — simpler to configure (a single VM-level property, no Key Vault dependency), and it covers more of the VM's storage surface (including the temp disk/cache, which ADE doesn't). The Key Vault was kept in the project for potential future use.

**RBAC role scoped to the VM resource, not the resource group.** The custom role's `assignableScopes` points to the VM's specific resource ID rather than the resource group, matching the stated requirement to scope access to that one VM. The tradeoff: this makes the role fragile — deleting and recreating the VM (which happened once during testing) orphans the role definition, since Azure ties a resource-scoped role to that resource's exact ID. A resource-group-scoped role would have survived, at the cost of being less precisely scoped.

**Hand-written Bicep instead of Azure Verified Modules (AVM).** Microsoft's current guidance recommends using pre-built AVM modules rather than writing resource definitions from scratch. I wrote this template by hand deliberately, to understand what's actually inside a VM/NIC/NSG resource definition before relying on an abstraction that hides those details. A production version of this template would likely reference AVM modules instead.

## Challenges & troubleshooting

**Free-tier VM capacity constraints.** Deploying even a small burstable VM hit `AllocationFailed` / `NotAvailableForSubscription` errors across four regions (Central US, East US, East US 2, Canada East) before succeeding in North Central US. Quota (what your subscription is *allowed* to request) and capacity (whether Azure's datacenters have *physical room* right now) are separate constraints — passing one doesn't guarantee the other. Confirmed via the Quotas blade that quota wasn't the blocker; capacity was.

**Stuck deployment from an immutable property.** A failed VM deployment left a "ghost" resource that blocked a redeploy attempt with `PropertyChangeNotAllowed` on the SSH key — Azure won't let you change an SSH key on an existing VM resource. Fixed by deleting the specific failed VM (and its orphaned OS disk) rather than the whole resource group, then redeploying against the existing, still-healthy networking resources.

**Accidental VM deletion during RBAC testing.** While verifying the custom role's deny-on-delete behavior, I attempted the delete from the wrong session and deleted the VM for real. After rebuilding it, I discovered the custom role itself had also been orphaned — a role scoped to a specific resource ID becomes unlistable once that resource no longer exists. Recreated the role against the new VM's resource ID and re-verified both directions of access.

**Cost Management scope confusion.** Attempting to create a budget from the top-level Billing Account view only showed billing-account-level scopes, not the subscription or resource group. Budgets scoped to a subscription/resource group need to be created from within that subscription's own Cost Management blade, not the billing account's.

## Verification

Every control in this project was tested, not just configured:

- **RBAC**: signed in as the scoped test user and confirmed they could view/start/stop the VM, but received `Authorization failed` when attempting to delete it
- **Tag policy**: attempted to create an untagged resource in the resource group and received a policy denial before deployment
- **Encryption at Host**: confirmed via `az vm show --query securityProfile.encryptionAtHost` returning `true`
- **Bicep template**: deployed end-to-end to a separate, clean resource group and verified SSH access to the resulting VM

*(Screenshots of each verification step are included below.)*

<img width="1496" height="835" alt="Verified Least Priviledge demo" src="https://github.com/user-attachments/assets/683ad0f3-13d9-4d05-a399-ece73254bd9d" />

<img width="685" height="421" alt="Require Tag Policy enforcement " src="https://github.com/user-attachments/assets/fd60f5bb-984e-4701-8c2c-fd5277a298fe" />

<img width="1934" height="868" alt="Require Tag Policy enforcement 2" src="https://github.com/user-attachments/assets/7d2963e6-646a-427b-9868-80a06235991d" />

<img width="552" height="204" alt="Encrption at Host validation " src="https://github.com/user-attachments/assets/f6f69bed-a8dc-4871-b620-d37424e2f1d9" />

<img width="810" height="697" alt="Encrpt at host validation portal view " src="https://github.com/user-attachments/assets/bba7a576-7911-42d4-8525-d119d5096d19" />






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

The custom RBAC role, tag policy, disk encryption, and cost budget are configured separately (via Portal/CLI) and are not yet part of the Bicep template — see Next steps.

## Next steps

- Extend `main.bicep` to include the custom RBAC role, tag policy assignment, and cost budget as code, rather than manual Portal/CLI steps
- Compare this hand-written template against an equivalent built from Azure Verified Modules
- Project 2 will extend this VNet with a second subnet for private endpoints and a secured storage account
