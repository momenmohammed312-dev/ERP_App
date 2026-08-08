#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Required runtime DLLs that must sit next to pos_offline_desktop.exe.
// If any is missing at startup, we show a clear Arabic/English message
// instead of letting the OS crash the app silently.
static const std::vector<LPCWSTR> kRequiredDlls = {
    L"flutter_windows.dll",
    L"app_links_plugin.dll",
    L"connectivity_plus_plugin.dll",
    L"desktop_window_plugin.dll",
    L"flutter_secure_storage_windows_plugin.dll",
    L"permission_handler_windows_plugin.dll",
    L"platform_device_id_windows_plugin.dll",
    L"printing_plugin.dll",
    L"screen_retriever_windows_plugin.dll",
    L"share_plus_plugin.dll",
    L"sqlite3_flutter_libs_plugin.dll",
    L"url_launcher_windows_plugin.dll",
    L"window_manager_plugin.dll",
};

// Returns the full path of the folder containing this executable.
static std::wstring GetExecutableDir() {
  std::wstring buffer(MAX_PATH, L'\0');
  while (true) {
    DWORD size = ::GetModuleFileNameW(nullptr, &buffer[0],
                                      static_cast<DWORD>(buffer.size()));
    if (size == 0) {
      return L"";
    }
    if (size < buffer.size()) {
      buffer.resize(size);
      break;
    }
    buffer.resize(buffer.size() * 2);
  }
  size_t slash = buffer.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L"";
  }
  return buffer.substr(0, slash);
}

// Returns the name of the first missing required DLL, or L"" if all exist.
static std::wstring FindFirstMissingDll() {
  std::wstring dir = GetExecutableDir();
  if (dir.empty()) {
    return L"<unknown - cannot locate executable folder>";
  }
  for (LPCWSTR dll : kRequiredDlls) {
    std::wstring path = dir + L"\\" + dll;
    DWORD attrs = ::GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
      return dll;
    }
  }
  return L"";
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Self-check: verify required DLLs exist before starting the engine.
  // A missing plugin DLL makes the OS refuse to launch the app at all, so
  // show a clear message telling the user to reinstall instead of failing
  // silently or with a cryptic loader error.
  std::wstring missing = FindFirstMissingDll();
  if (!missing.empty()) {
    ::MessageBoxW(nullptr,
                  (L"ملف مفقود من مجلد البرنامج: " + missing +
                   L"\nيرجى إعادة تثبيت البرنامج بشكل كامل."
                   L"\n\nMissing file in program folder: " + missing +
                   L"\nPlease reinstall the application completely.")
                      .c_str(),
                  L"POS System - ملف ناقص / Missing file",
                  MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"pos_offline_desktop", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
