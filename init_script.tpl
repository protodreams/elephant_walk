#!/bin/bash
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
    
yum  update -y
yum install -y util-linux e2fsprogs

aws ec2 attach-volume --volume-id vol-031ef9d249e590f68 --instance-id $(curl http://169.254.169.254/latest/meta-data/instance-id) --device /dev/nvme2n1
              # Wait for the volume to be attached
              while [ ! -e /dev/nvme2n1 ]; do sleep 1; done
              # Create a file system on the volume if it does not have one
              file -s /dev/nvme2n1 | grep -q ext4 || mkfs -t ext4 /dev/nvme2n1
              # Create a mount point
              mkdir /mnt/caves_of_steel
              # Mount the EBS volume
              mount /dev/nvme2n1 /mnt/caves_of_steel
              # Add an entry to /etc/fstab to mount the volume on reboot
              echo '/dev/nvme2n1 /mnt/caves_of_steel ext4 defaults,nofail 0 2' >> /etc/fstab
              EOF

mkdir -p /mnt/caves_of_steel
mount  -t  ext4 /dev/nvme1n1 /mnt/caves_of_steel
              