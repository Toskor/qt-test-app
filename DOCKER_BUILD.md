# Инструкция по сборке через Docker

## Быстрый старт

На macOS выполните:

```bash
./build-windows.sh Release
```

Готовые файлы будут в `build-windows/deploy/`.

## Подробное описание процесса

### Шаг 1: Установка Docker Desktop

Убедитесь, что у вас установлен Docker Desktop для macOS:

- Скачайте с [docker.com](https://www.docker.com/products/docker-desktop)
- Установите и запустите Docker Desktop

### Шаг 2: Первая сборка

При первой сборке Docker образ будет собираться долго (30-60 минут), так как MXE компилирует Qt6 из исходников. Это происходит только один раз.

```bash
./build-windows.sh Release
```

### Шаг 3: Последующие сборки

После первой сборки образ будет кэширован, и последующие сборки будут выполняться намного быстрее (несколько минут).

## Структура файлов

- `Dockerfile` - определение Docker образа с MXE и Qt6
- `docker-compose.yml` - конфигурация для удобной сборки
- `build-windows.sh` - скрипт автоматизации сборки
- `.dockerignore` - файлы, исключаемые из Docker контекста

## Ручная сборка (без скрипта)

Если хотите выполнить сборку вручную:

```bash
# Сборка образа
docker-compose build

# Запуск интерактивной сессии
docker-compose run --rm builder

# Внутри контейнера:
cmake -B build-windows \
    -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=/usr/lib/mxe/usr/x86_64-w64-mingw32.static/share/cmake/mxe-conf.cmake \
    -DCMAKE_PREFIX_PATH=/usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6

cmake --build build-windows

# Развертывание DLL
/usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/windeployqt.exe \
    --compiler-runtime \
    --release \
    --dir build-windows/deploy \
    build-windows/qt-test-app.exe
```

## Устранение неполадок

### Проблема: Docker образ не собирается

**Решение:** Убедитесь, что Docker Desktop запущен и имеет достаточно ресурсов (рекомендуется минимум 4GB RAM).

### Проблема: Ошибка при компиляции Qt6 в MXE

**Решение:** Это может занять очень много времени. Убедитесь, что у вас достаточно места на диске (минимум 10GB свободного места).

### Проблема: windeployqt не найден

**Решение:** Проверьте, что Qt6 установлен в MXE:

```bash
docker-compose run --rm builder ls -la /usr/lib/mxe/usr/x86_64-w64-mingw32.static/qt6/bin/
```

### Проблема: Исполняемый файл не запускается на Windows

**Решение:** Убедитесь, что все необходимые DLL скопированы. Проверьте папку `build-windows/deploy/` и убедитесь, что там есть все необходимые файлы.

## Альтернативные подходы

Если MXE не работает или сборка занимает слишком много времени, рассмотрите альтернативы:

1. **GitHub Actions** - настройте CI/CD для автоматической сборки на Windows
2. **Windows VM** - используйте виртуальную машину Windows на macOS
3. **Облачная сборка** - используйте сервисы вроде AppVeyor или Azure DevOps

## Дополнительная информация

- [MXE документация](https://mxe.cc/)
- [Qt кросс-компиляция](https://doc.qt.io/qt-6/linux-building.html)
- [Docker документация](https://docs.docker.com/)
