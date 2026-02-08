# 1. 鍵を配置するためのディレクトリ構造を作成
mkdir -p ./secrets/nas/etc/tpm-init
mkdir -p ./secrets/nas/tmp
mkdir -p ./secrets/nas/etc/ssh

# 2. マスターキーをローカルで生成（これがバックアップになります）
dd if=/dev/urandom of=./secrets/nas/etc/tpm-init/master.key bs=1 count=32
echo "Master key generated: ./secrets/nas/etc/tpm-init/master.key"

# 3. LUKSパスワードの安全な入力 (プロンプト)
echo -n "Enter LUKS password: "
read -rs PASSWORD
echo "$PASSWORD" > ./secrets/nas/etc/luks-secret.password
echo -e "\nPassword saved to ./secrets/nas/etc/luks-secret.password"

# 4. SSH CA鍵ペアの作成
if [ ! -f "~/ssh-ca/ssh_ca_key" ]; then
    mkdir -p ~/ssh-ca
    ssh-keygen -t ed25519 -f ~/ssh-ca/ssh_ca_key -C "NAS_SSH_CA" -N ""
fi
cp ~/ssh-ca/ssh_ca_key.pub ./secrets/nas/etc/ssh/trusted-user-ca-keys.pem

echo "Preparation complete. You can now run nixos-anywhere."

# デスクトップPCの公開鍵を署名して、1日間有効な証明書を発行する例
# -s: CA秘密鍵, -I: 識別子, -n: 許可するユーザー名, -V: 有効期限
# cd ~/ssh-ca
# ssh-keygen -s ssh_ca_key -I "user_access" -n root -V +1d id_ed25519.pub