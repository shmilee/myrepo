# Maintainer: shmilee <echo c2htaWxlZS56anVAZ21haWwuY29tCg==|base64 -d>
pkgname=myrepo-git
_gitname="myrepo"
pkgver=0.0.1
pkgrel=1
pkgdesc="Add, remove, check and update packages(from AUR) for my personal repo."
arch=('any')
url="https://github.com/shmilee/myrepo"
license=('GPL')
depends=('pacman' 'grep' 'devtools')
optdepends=('python: multi-threads get AUR information')
backup=('etc/myrepo.conf')
source=("git+https://github.com/shmilee/${_gitname}.git")
md5sums=('SKIP')

pkgver() {
  cd "$srcdir/$_gitname"
  echo -n "0.$(git rev-list --count HEAD)."
  git describe --always|sed 's|-|.|g'
}

build() {
    cd "$srcdir/$_gitname/po"
    for lan in *.po; do
        msgfmt $lan -o ${lan%.po}.mo
    done
}

package() {
    cd "$srcdir/$_gitname"
    install -Dm644 etc/myrepo.conf "$pkgdir"/etc/myrepo.conf
    install -Dm755 bin/myrepo.sh "$pkgdir"/usr/bin/myrepo
    cd lib/
    for file in base.sh cmds.sh utils.sh multi-dl.py dl_aur_info.sh; do
        install -Dm755 $file "$pkgdir"/usr/lib/myrepo/$file
    done
    cd ../po/
    for lan in *.mo; do
        install -Dm644 $lan "$pkgdir"/usr/share/locale/${lan%.mo}/LC_MESSAGES/myrepo.mo
    done
}
