Write-Output "Running Terraform..."
cd infrastructure/terraform
terraform init
terraform apply -auto-approve

Write-Output "Running Ansible..."
cd ../ansible
ansible-playbook playbook.yml
