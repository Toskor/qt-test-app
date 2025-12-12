# qt-test-app

Простое Qt приложение для тестирования.

## Сборка проекта

### Кросс-компиляция для Windows на macOS через Docker

Этот проект поддерживает кросс-компиляцию для Windows на macOS с использованием Docker и MXE (M cross environment).

#### Требования для Docker сборки

- Docker Desktop для macOS
- Docker Compose (обычно входит в Docker Desktop)

#### Быстрая сборка

Просто запустите скрипт сборки:

```bash
./build-windows.sh Release
```

или для Debug версии:

```bash
./build-windows.sh Debug
```

После завершения сборки все файлы (.exe и .dll) будут находиться в папке `build-windows/deploy/`.

#### Ручная сборка через Docker Compose

```bash
# Сборка образа (только первый раз или после изменений Dockerfile)
docker-compose build

# Запуск сборки
docker-compose run --rm builder
```

#### Что происходит при сборке

1. Docker образ собирается на основе MXE (M cross environment)
2. Устанавливаются необходимые компоненты Qt6 через MXE
3. Проект компилируется с использованием кросс-компилятора MinGW
4. Автоматически выполняется `windeployqt` для копирования всех необходимых DLL

#### Структура файлов для Docker

- `Dockerfile` - определение Docker образа с MXE и Qt6
- `docker-compose.yml` - конфигурация для удобной сборки
- `build-windows.sh` - скрипт автоматизации сборки
- `.dockerignore` - файлы, исключаемые из Docker контекста

---

## Локальная сборка на Windows

### Требования

- Qt 6.9.2 (или выше)
- CMake 3.16+
- MinGW 64-bit компилятор

**Должно быть в PATH:**

- CMake (`cmake.exe`)
- MinGW компилятор (`g++.exe`, `gcc.exe`)
- MinGW Make (`mingw32-make.exe`)
- Qt bin (`windeployqt.exe`, `qmake.exe`)

**Переменные окружения:**

- `CMAKE_PREFIX_PATH` - путь к Qt (например, `C:\Qt\6.9.2\mingw_64`)
- `QT_DIR` - путь к Qt (например, `C:\Qt\6.9.2\mingw_64`)

### Сборка Debug версии через консоль

```bash
mkdir build-debug
cd build-debug
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug
cmake --build .
```

Исполняемый файл будет находиться в `build-debug/qt-test-app.exe`

### Сборка Release версии через консоль

```bash
mkdir build-release
cd build-release
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

Исполняемый файл будет находиться в `build-release/qt-test-app.exe`

## Получение бинарников и DLL файлов

После сборки для получения всех необходимых DLL файлов используйте `windeployqt`:

### Для Debug версии:

```cmd
windeployqt.exe --compiler-runtime --dir deploy-debug build-debug\qt-test-app.exe
```

### Для Release версии:

```cmd
windeployqt.exe --compiler-runtime --release --dir deploy-release build-release\qt-test-app.exe
```

Утилита `windeployqt` находится в папке установки Qt, например:

- `C:\Qt\6.9.2\mingw_64\bin\windeployqt.exe`

После выполнения команды все необходимые DLL файлы будут скопированы в указанную папку вместе с исполняемым файлом.
