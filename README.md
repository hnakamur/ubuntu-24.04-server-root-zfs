# ubuntu-24.04-server-root-zfs

Ubuntu 24.04のサーバー版をrootパーティションをZFSでインストールするのを半自動化するスクリプトです。

以下のページを参考にしました。

* [Ubuntu 22.04 Root on ZFS — OpenZFS documentation](https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2022.04%20Root%20on%20ZFS.html)
* [Ubuntu24 LTSをroot on ZFSでインストールする](https://zenn.dev/he/articles/2f82142e24ef35)
* [Ubuntu Server 24.04をroot on ZFS、LUKS暗号化、TPM自動復号でインストールする](https://zenn.dev/khu/articles/5fbcd426a50d3f)

このスクリプトではbootパーティション、rootパーティションともに圧縮なしとしています。

## 事前準備と設定調整

* https://jp.ubuntu.com/download からUbuntu Server 24.04 LTSのISOイメージをダウンロードし `ubuntu-24.04-live-server-amd64.iso` というファイル名でこのディレクトリに保存します。
* Makefile で設定している変数や install-zfs-server.sh のパーティション作成のサイズなどを適宜調整してください。

## 仮想マシンでのインストール手順

1. 以下のコマンドを実行してインストーラのISOイメージを起動します。
   ```
   make boot_from_cdrom
   ```
2. DHCPでアドレスを取得するところまで進んだら、HelpのEnter Shellを選んでシェルに入ります。
3. SSHの公開鍵を`/root/.ssh/authorized_keys`に保存します。例えば以下のように実行します。
   ```
   curl -sSLo /root/.ssh/authorized_keys https://github.com/hnakamur.keys
   ```
4. 以下のコマンドを実行しIPアドレスを確認します。
   ```
   ip a
   ```
5. 別の端末を開いて以下のコマンドを実行し、インストールスクリプトをコピーして実行します。
   ```
   IP=上で確認したアドレス make install
   ```
6. インストールが終わってpoweroffが実行されたら、ISOイメージを起動した端末に戻ってCtrl-Cで終了します。
7. 以下のコマンドを実行してディスクから起動します。
   ```
   make boot_from_disk
   ```
8. 初回の起動時はZFSのrpoolがマウントできずに`(initramfs)`のプロンプトが表示されるので、
   ```
   zpool import -f rpool
   ```
   を入力し、次の`(initramfs)`のプロンプトで
   ```
   exit
   ```
   を入力します。
   するとブートの続きが実行されログインプロンプトが表示されます。
