# Автоматическая настройка виртуальных машин

## Создание и запуск машин в rescue режим

Для того, чтобы мы могли настроить виртуальные машины, на них должна быть запущена какая-нибудь rescue система
(systemrescuecd, gentoo minimal install и т.д.), должна быть настроена сеть (желательно, чтобы виртуальной машине
был присвоен именно тот ip адрес, который им будет использоваться далее - так будет проще с ansible), а также
надо, чтобы был настроен доступ к этой виртуальной машине.

В качестве rescue системы выберем gentoo minimal - будет проще его модифицировать под наши нужды.
Тут также есть два варианта загрузки.

### Загрузка через install cd (iso).

По стандарту gentoo minimal запускается без запущенного sshd и с случайным паролем на root.
В такой конфигурации мы не сможем автоматически войти в систему - это требует ручного вмешательства
(запуск sshd и изменение пароля на root). Поэтому мы сделаем модификацию iso.

Все операции будем делать из-под root. Для начала примонтируем iso файл:

```
mkdir iso-mount
mount -o loop gentoo-minimal-install.iso iso-mount
```

Далее скопируем все файлы в новый каталог, чтобы их можно было модифицировать
(так как cp запускается из-под root'а, то копирование будет с сохранением всех аттрибутов):

```
mkdir iso-new
cp -r iso-mount/* iso-new/
```

Не забываем убрать mount:

```
umount iso-mount
rm -rf iso-mount
```

Для того, чтобы запустить sshd и выставить пароль (плюс ещё уберём интерактивный запрос на выставление keymap'а
для не en языка) нам достаточно прописать параметры запуска ядра (параметры поддерживаются самой iso):
`dosshd nokeymap passwd=1`. Пароль при этом будет выставлен в единицу.

Параметры прописываются в файле `grub/grub.cfg` и `isolinux/isolinux.cfg`.

После этого можно пересобрать iso файл (для этого нам нужен будет установленный пакет `cdrtools`):

```
mkisofs -J -R -l -V "Gentoo Linux - AMD64" \
  -o gentoo-minimal-install-insecure.iso \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -b gentoo.efimg \
  -c boot.cat \
  -no-emul-boot \
  -z \
  iso-new/
```

После старта системы к ней можно будет достучаться по ssh с логином root и паролем '1'.

### Загрузка через PXE

Модификация iso достаточно простая, но у неё есть один нюанс - доступ по паролю и не secure rescue образ,
который может куда-нибудь случайно попасть. Также мы не можем динамически генерировать параметры под локальную систему.
Загрузка через PXE может решить этот вопрос.

Для libvirt нам надо будет следующее:
* dnsmasq должен быть скомпилирован с поддержкой tftp
* надо настроить tftp и bootp параметры для сети, с которой будем запускаться в libvirt:
https://lathama.net/PXE_boot_with_Libvirt - в качестве boot'а будем использовать pxelinux.0 из syslinux
* в параметрах запуска в самой виртуальной машине нам надо будет разрешить запуск с сетевой карты и поставить
его вторым после запуска с drive'а.

Для virtualbox:
* TODO - https://github.com/defunctzombie/virtualbox-pxe-boot/blob/master/README.md

Подготовим теперь папку, в которой лежат файлы для tftp. Скопируем необходимый минимум из пакета syslinux:

```
cp /usr/lib/syslinux/{pxelinux.0,ldlinux.c32} tftp/
```

Создадим конфигурацию запуска в `tftp/pxelinux.cfg`:

```
DEFAULT gentoo

LABEL gentoo
    kernel boot/gentoo root=/dev/ram0 init=/linuxrc loop=boot/image.squashfs looptype=squashfs cdroot=1 real_root=/ dosshd nokeymap
    append initrd=boot/gentoo.igz
MENU LABEL gentoo
```

Ядро скопируем из распакованного ранее iso: `cp boot/gentoo tftp/boot/gentoo`.
Предварительно надо создать сам каталог - `mkdir tftp/boot`.

А вот с initrd и образом squashfs всё чуть сложнее. Для того, чтобы нам не надо было поднимать дополнительно nfs
и подобные ему, нам понадобится сам образ внести в initrd.

Распаковываем старый initrd:

```
mkdir initrd
cd initrd
xz -dc ../gentoo.igz | cpio -id
```

Модифицируем `init` файл с помощью [initrd.patch](initrd.patch). Данный патч добавляет несколько возможностей:

* `sshkey` - ssh ключ для root пользователя, должен быть закодирован в base64 формате
* `net.conf` - конфигурация сетевых карт (надо для virtualbox где не так просто настроить отдельный
нормальный dhcp сервер по mac адресу карты)
* `dns` - конфигурирование nameserver'ов через kernel параметры

`net.conf` имеет вид: `if=<name|mac>,dhcp,if=<name|mac>,ip=<static_ip>,gw=<gateway_ip>`

В опции в `tftp/pxelinut.cdf/default` добавляем `sshkey=XXX`, где xxx получается следующим образом:

```
cat ~/.ssh/id_ed25519.pub | base64
```

Переупаковывем initrd:

```
cd initrd
find . -print | cpio -o -H newc | gzip -9 -c - > ../gentoo.igz
```

## Автоматические IP адрес для систем

Для автоматической настройк нам не хватает только правильного IP адреса у загруженной в rescue системы

### libvirtd

Воспользуемся гайдом: https://www.cyberciti.biz/faq/linux-kvm-libvirt-dnsmasq-dhcp-static-ip-address-configuration-for-guest-os/

В секцию dhcp в настройках сети для этого достаточно заранее прописать ip адреса, связанные с mac адресами сетевых
карт виртуальных машин. Имя машины указывать не обязательно:

```
<dhcp>
  ...
  <host mac='52:54:00:1b:bb:5f' ip='192.168.122.4'/>
  ...
</dhcp>
```

### virtualbox
TODO
