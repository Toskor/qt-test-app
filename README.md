# qt-test-app

Простое Qt приложение для тестирования.

## Сборка проекта

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
