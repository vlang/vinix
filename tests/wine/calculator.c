#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { DISPLAY_ID = 100, CLEAR_ID, EQUALS_ID };

static HWND display;
static double accumulator;
static char pending_operator;
static int replace_display = 1;

static double display_value(void) {
    char text[64];
    GetWindowTextA(display, text, sizeof(text));
    return strtod(text, NULL);
}

static void show_value(double value) {
    char text[64];
    snprintf(text, sizeof(text), "%.12g", value);
    SetWindowTextA(display, text);
}

static double calculate(double left, double right, char operation) {
    switch (operation) {
    case '+': return left + right;
    case '-': return left - right;
    case '*': return left * right;
    case '/': return right == 0.0 ? 0.0 : left / right;
    default: return right;
    }
}

static void push_digit(char digit) {
    char text[64];
    size_t length;

    if (replace_display) {
        text[0] = digit;
        text[1] = '\0';
        replace_display = 0;
    } else {
        GetWindowTextA(display, text, sizeof(text));
        length = strlen(text);
        if (length + 1 < sizeof(text)) {
            text[length] = digit;
            text[length + 1] = '\0';
        }
    }
    SetWindowTextA(display, text);
}

static LRESULT CALLBACK window_proc(HWND window, UINT message,
                                    WPARAM wparam, LPARAM lparam) {
    (void)lparam;
    if (message == WM_COMMAND) {
        int id = LOWORD(wparam);
        if (id >= '0' && id <= '9') {
            push_digit((char)id);
            return 0;
        }
        if (id == CLEAR_ID) {
            accumulator = 0.0;
            pending_operator = 0;
            replace_display = 1;
            SetWindowTextA(display, "0");
            return 0;
        }
        if (id == '+' || id == '-' || id == '*' || id == '/') {
            accumulator = pending_operator
                ? calculate(accumulator, display_value(), pending_operator)
                : display_value();
            show_value(accumulator);
            pending_operator = (char)id;
            replace_display = 1;
            return 0;
        }
        if (id == EQUALS_ID) {
            if (pending_operator) {
                accumulator = calculate(accumulator, display_value(), pending_operator);
                show_value(accumulator);
                pending_operator = 0;
            }
            replace_display = 1;
            return 0;
        }
    }
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(window, message, wparam, lparam);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line,
                   int show_command) {
    static const char class_name[] = "VinixWineCalculator";
    static const char *labels[] = {
        "7", "8", "9", "/",
        "4", "5", "6", "*",
        "1", "2", "3", "-",
        "C", "0", "=", "+"
    };
    WNDCLASSA window_class = {0};
    HWND window;
    HFONT font;
    MSG message;
    int index;

    (void)previous;
    (void)command_line;
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursor(NULL, IDC_ARROW);
    window_class.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    window_class.lpszClassName = class_name;
    if (!RegisterClassA(&window_class))
        return 1;

    window = CreateWindowExA(0, class_name, "Calculator",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 326, 430,
        NULL, NULL, instance, NULL);
    if (!window)
        return 1;

    font = CreateFontA(24, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, "Segoe UI");
    display = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "0",
        WS_CHILD | WS_VISIBLE | ES_RIGHT | ES_READONLY,
        16, 18, 278, 58, window, (HMENU)(INT_PTR)DISPLAY_ID, instance, NULL);
    SendMessage(display, WM_SETFONT, (WPARAM)font, TRUE);

    for (index = 0; index < 16; ++index) {
        int row = index / 4;
        int column = index % 4;
        int id;
        HWND button;
        if (labels[index][0] >= '0' && labels[index][0] <= '9')
            id = labels[index][0];
        else if (labels[index][0] == 'C')
            id = CLEAR_ID;
        else if (labels[index][0] == '=')
            id = EQUALS_ID;
        else
            id = labels[index][0];
        button = CreateWindowExA(0, "BUTTON", labels[index],
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            16 + column * 71, 92 + row * 70, 65, 60,
            window, (HMENU)(INT_PTR)id, instance, NULL);
        SendMessage(button, WM_SETFONT, (WPARAM)font, TRUE);
    }

    ShowWindow(window, show_command);
    UpdateWindow(window);
    while (GetMessage(&message, NULL, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessage(&message);
    }
    DeleteObject(font);
    return (int)message.wParam;
}
