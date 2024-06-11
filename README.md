sudo apt install ansible
ansible-playbook -K newInstall.yml

ansible-playbook -vvv -i inventory.yml -l nas nas.yml --ask-become-pass