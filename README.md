# HashiCorp Vault on Azure Tutorial

This tutorial uses Terraform to bootstrap a HashiCorp Vault server running in dev mode and walks through how to enable the [Azure Auth Method](https://www.vaultproject.io/docs/auth/azure.html) that can be used to [authenticate](https://www.vaultproject.io/docs/concepts/auth.html#authenticating) with Vault.

## Prerequisites 

Install Azure CLI

```bash
brew update && brew install azure-cli
```

Perform a login into Microsoft Azure account

```bash
az login
```

Once logged in, list all subscriptions

```bash
az account list
```

```bash
[
  {
    "cloudName": "AzureCloud",
    "id": "00000000-0000-0000-0000-000000000000",
    "isDefault": true,
    "name": "PAYG Subscription",
    "state": "Enabled",
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "user": {
      "name": "user@example.com",
      "type": "user"
    }
  }
]
```

Set a default subscription using the `id` field from the above response. You may want to use one of the subscriptions 
as the default subscription to use with Terraform.

```bash
az account set --subscription="$SUBSCRIPTION_ID"
```

Clone git repository

```bash
git clone https://github.com/anubhavmishra/vault-on-azure.git
```

## Usage

Create Azure infrastructure for the vault demo 

```bash
cd vault-on-azure 
```

Initialize Terraform

```bash
terraform init
```

Execute Terraform Apply

```bash
terraform apply
```

*Enter "yes" to create the resources*

After the `terraform apply` is complete, expect an output like this

```bash
Apply complete! Resources: 5 added, 0 changed, 2 destroyed.

Outputs:

vault-demo_private_ip = x.x.x.x
vault-demo_public_ip = x.x.x.x
vault-demo_ssh = ssh azureuser@x.x.x.x -i /Users/username/projects/terraform-vault-azurerm/.ssh/id_rsa
```

SSH into the vault demo server 

```bash
$(terraform output vault-demo_ssh)
```

*The above command will also create a tunnel from the local machine where Terraform is being executed from to the
virtual machine running Vault.*

Perform a vault root login

```bash
vault login "root"
```

**WARNING: This is not a best practice for running Vault in production. This is only done for the demo purposes.**


```bash
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                Value
---                -----
token              root
token_accessor     ddb2366e-e853-e26d-b19d-df56ba89bce2
token_duration     ∞
token_renewable    false
token_policies     [root]
```

On local machine, open http://localhost:8200 in the browser

Open a new terminal window to run the command below.

```bash
open http://localhost:8200
```

Login with password `root`

### Enable Azure Auth Method

Follow the docs [here](https://www.vaultproject.io/docs/auth/azure.html#via-the-cli-1) to enable and configure the Azure Auth Method using the CLI.

Follow the steps below for configuring it using the UI

* Go to "Settings" in the Vault UI located at http://localhost:8200/ui/vault/secrets.
* Select "Auth Methods" from the left sidebar.
* Select "Azure" from the "Type dropdown.
* In the "Tenant ID" field, enter the Directory ID from the Active Directory Menu blade in the "Properties" section of the Azure console. 
* In the "Resource" field, enter "https://management.azure.com/".
* Expand the "Azure Options" section and enter the "Client ID" and "Client secret" for the application. 
* Click on the "Enable Method" button.

You have successfully mounted the Azure Auth Method.


### Create Vault Policy

SSH into the vault demo server 

```bash
$(terraform output vault-demo_ssh)
```

*The above command will also create a tunnel from the local machine where Terraform is being executed from to the
virtual machine running Vault.*

Perform a vault root login

```bash
vault login "root"
```

Write a dev policy file 

```bash
echo 'path "secret/example" {
  capabilities = ["read", "list"]
}' > dev.hcl
```

Create a policy called "dev" in vault

```bash
vault policy write dev dev.hcl
```

### Create a Vault Role

Create a role called "dev-role" in vault and associate the "dev" policy to it

```bash
vault write auth/azure/role/dev-role \
    policies="dev" \
    bound_subscription_ids=SUBSCRIPTION_ID \
    bound_resource_groups=azure-vault-demo \
    ttl=24h \
    max_ttl=48h
```

### Write Secrets into Vault

Store some example secrets into vault

```bash
vault kv put secret/example foo=bar
```

Read the secrets using the CLI

```bash
vault kv get secret/example
```

Expected output

```bash
====== Metadata ======
Key              Value
---              -----
created_time     2018-05-23T02:07:57.96424783Z
deletion_time    n/a
destroyed        false
version          1

=== Data ===
Key    Value
---    -----
foo    bar
```

### Perform a Vault Login using Azure Auth Method

Get JWT token from Azure Resource Manager

```bash
curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -H Metadata:true
```

Expected output

```bash
eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6ImlCakwxUmNxemhpeTRmcHhJeGRacW9oTTJZayIsImtpZCI6ImlCakwxUmNxemhpeTRmcHhJeGRacW9oTTJZayJ9.eyJhdWQiOiJodHRwczovL21hbmFnZW1lbnQuYXp1cmUuY29tLyIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzBlM2UyZTg4LThjYWYtNDFjYS1iNGRhLWUzYjMzYjZjNTJlYy8iLCJpYXQiOjE1MjcwNDA2OTIsIm5iZiI6MTUyNzA0MDY5MiwiZXhwIjoxNTI3MDQ0NTkyLCJhaW8iOiJZMmRnWUdqTVk5ZzMvU0x2cjRmTS96c0QyellvO4Qf2sQHeqYW3YyxcWxXrAyohi-0SLgQ34rOXDUKyNpPY1mFtRJLRk_mx_jYJcJVW_PDXsJYAitvsoI51DIqS0ZqPWcdKN0TGYOtzmzSUO0rUqJslXgEHET-7Fn2huMHeuk99fmtB_t15-8IeEpgNadycJvdvSbq3c0Zv4WNRNSO4zcRcmd8nAHi3Xqw3K8yulDk9jxDmHtEtSsekU_gupt0XuBnzMeRViN6woeiQa8PfI4Zzz6Fp-Viep_5a8jVz5_SPhvhbF57On5he3LYK3fxGBSYw-29w5lGNqhdj_rUgb17cGvm9wMS-SgvcW6RvVXuzkNszwAjiOjQYtTf2g
```

Perform vault login

```bash
vault write auth/azure/login role="dev-role" jwt="JWT_TOKEN_HERE" subscription_id="SUBSCRIPTION_ID" resource_group_name="RESOURCE_GROUP_NAME" vm_name="VM_NAME"
```

Expected output

```bash
Key                Value
---                -----
token              430a2bfc-f660-e867-092a-bdd69b629e19
token_accessor     f3988a11-c099-1926-27c4-1274b9cce50a
token_duration     24h
token_renewable    true
token_policies     [default dev]
token_meta_role    dev-role
```

In order to auto inject the vault token into the environment, use the command below

```bash
export VAULT_TOKEN=$(vault write -field=token auth/azure/login role="dev-role" jwt="" subscription_id="SUBSCRIPTION_ID" resource_group_name="RESOURCE_GROUP_NAME" vm_name="VM_NAME")
```

*The `field=token` option filters the results and only returns the vault token.*

Read secrets for the example application

```bash
vault kv get secret/example
```

Expected output

```bash
====== Metadata ======
Key              Value
---              -----
created_time     2018-05-23T02:07:57.96424783Z
deletion_time    n/a
destroyed        false
version          1

=== Data ===
Key    Value
---    -----
foo    bar
```

Try reading a secret that isn't specified in the vault policy

```bash
vault kv get secret/foo
```

Expected output

```bash
Error reading secret/data/foo: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/foo
Code: 403. Errors:

* permission denied
```
