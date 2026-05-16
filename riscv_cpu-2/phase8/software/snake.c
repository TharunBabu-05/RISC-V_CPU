/* ============================================================
 *  snake.c  —  Classic Snake Game for the RV32 SoC
 *
 *  Runs on our custom RISC-V processor on the Arty S7 FPGA.
 *  Uses UART serial terminal (115200 baud) via PuTTY/TeraTerm.
 *  Requires a terminal with ANSI escape code support.
 *
 *  Controls (WASD keys):
 *    W = Up    S = Down    A = Left    D = Right
 *    Q = Quit
 *
 *  Terminal size assumed: 80 columns × 24 rows
 *  Game field: 40×20 cells with a border
 * ============================================================ */

#include "uart.h"
#include "soc.h"
#include <stdint.h>

/* ============================================================
 *  Game Configuration
 * ============================================================ */
#define FIELD_W     38      /* Inner playfield width  (cols) */
#define FIELD_H     18      /* Inner playfield height (rows) */
#define FIELD_X      2      /* Terminal column of left border  */
#define FIELD_Y      3      /* Terminal row    of top border   */
#define MAX_SNAKE  256      /* Maximum snake length            */
#define INIT_LEN     4      /* Starting snake length           */

/* Delay between game ticks (busy-loop cycles) */
/* Tune this value to set the game speed:
 *   Larger = slower snake.  ~100MHz CPU, so 2_000_000 ≈ ~20ms per tick */
#define TICK_DELAY  3000000

/* ============================================================
 *  Data Types
 * ============================================================ */
typedef struct {
    int x, y;  /* Field coordinates: x=col, y=row (0-indexed inside border) */
} Point;

/* ============================================================
 *  Game State
 * ============================================================ */
static Point  snake[MAX_SNAKE];  /* Snake body — head is snake[0] */
static int    snake_len;
static Point  food;
static int    dir_x, dir_y;     /* Current direction */
static int    score;
static int    game_over;

/* ============================================================
 *  Pseudo-Random Number Generator (LCG)
 *  Simple but good enough for food placement.
 * ============================================================ */
static uint32_t rng_state = 0xDEADBEEF;

static uint32_t rand_next(void) {
    rng_state = rng_state * 1664525U + 1013904223U;
    return rng_state;
}

/* ============================================================
 *  Busy-Wait Delay
 * ============================================================ */
static void delay(uint32_t n) {
    volatile uint32_t i;
    for (i = 0; i < n; i++) {
        __asm__ volatile ("nop");
    }
}

/* ============================================================
 *  Drawing Helpers
 * ============================================================ */

/* Draw a character at a field position (converts to terminal coords) */
static void draw_at(int fx, int fy, char ch) {
    uart_move_cursor(FIELD_Y + 1 + fy, FIELD_X + 1 + fx);
    uart_putc(ch);
}

/* Draw the static border (only once at start) */
static void draw_border(void) {
    int x, y;

    /* Top border */
    uart_move_cursor(FIELD_Y, FIELD_X);
    uart_putc('+');
    for (x = 0; x < FIELD_W; x++) uart_putc('-');
    uart_putc('+');

    /* Side borders */
    for (y = 0; y < FIELD_H; y++) {
        uart_move_cursor(FIELD_Y + 1 + y, FIELD_X);
        uart_putc('|');
        uart_move_cursor(FIELD_Y + 1 + y, FIELD_X + 1 + FIELD_W);
        uart_putc('|');
    }

    /* Bottom border */
    uart_move_cursor(FIELD_Y + 1 + FIELD_H, FIELD_X);
    uart_putc('+');
    for (x = 0; x < FIELD_W; x++) uart_putc('-');
    uart_putc('+');
}

/* Draw score line above the border */
static void draw_score(void) {
    uart_move_cursor(1, 1);
    uart_puts("  RISC-V Snake  |  Score: ");
    uart_print_int(score);
    uart_puts("   |  Controls: W=Up  S=Down  A=Left  D=Right  Q=Quit");
}

/* Draw the food item */
static void draw_food(void) {
    draw_at(food.x, food.y, '*');
}

/* Place food at a random empty position */
static void place_food(void) {
    int i, ok;
    do {
        food.x = (int)(rand_next() % (uint32_t)FIELD_W);
        food.y = (int)(rand_next() % (uint32_t)FIELD_H);
        ok = 1;
        for (i = 0; i < snake_len; i++) {
            if (snake[i].x == food.x && snake[i].y == food.y) {
                ok = 0; break;
            }
        }
    } while (!ok);
    draw_food();
}

/* ============================================================
 *  Game Initialization
 * ============================================================ */
static void game_init(void) {
    int i;

    /* Snake starts in the middle, moving right */
    snake_len = INIT_LEN;
    for (i = 0; i < snake_len; i++) {
        snake[i].x = FIELD_W / 2 - i;
        snake[i].y = FIELD_H / 2;
    }
    dir_x  = 1;  dir_y = 0;
    score  = 0;
    game_over = 0;

    /* Draw initial scene */
    uart_clear_screen();
    uart_hide_cursor();
    draw_border();
    draw_score();

    /* Draw initial snake */
    for (i = 0; i < snake_len; i++) {
        draw_at(snake[i].x, snake[i].y, (i == 0) ? '@' : 'o');
    }

    place_food();
}

/* ============================================================
 *  Read Direction from Keyboard (non-blocking)
 * ============================================================ */
static void read_input(void) {
    char c;
    if (!uart_kbhit()) return;
    c = uart_getc();

    switch (c) {
        case 'w': case 'W':
            if (dir_y != 1)  { dir_x = 0;  dir_y = -1; }
            break;
        case 's': case 'S':
            if (dir_y != -1) { dir_x = 0;  dir_y =  1; }
            break;
        case 'a': case 'A':
            if (dir_x != 1)  { dir_x = -1; dir_y =  0; }
            break;
        case 'd': case 'D':
            if (dir_x != -1) { dir_x =  1; dir_y =  0; }
            break;
        case 'q': case 'Q':
            game_over = 1;
            break;
    }
}

/* ============================================================
 *  Game Tick: Move snake, check collisions, eat food
 * ============================================================ */
static void game_tick(void) {
    Point new_head;
    int   ate_food = 0;
    int   i;

    new_head.x = snake[0].x + dir_x;
    new_head.y = snake[0].y + dir_y;

    /* ---- Check wall collision ---- */
    if (new_head.x < 0 || new_head.x >= FIELD_W ||
        new_head.y < 0 || new_head.y >= FIELD_H) {
        game_over = 1;
        return;
    }

    /* ---- Check self collision ---- */
    for (i = 0; i < snake_len - 1; i++) {
        if (snake[i].x == new_head.x && snake[i].y == new_head.y) {
            game_over = 1;
            return;
        }
    }

    /* ---- Check food ---- */
    if (new_head.x == food.x && new_head.y == food.y) {
        ate_food = 1;
        score += 10;
        draw_score();
    }

    /* ---- Erase tail (unless we ate food) ---- */
    if (!ate_food) {
        draw_at(snake[snake_len - 1].x, snake[snake_len - 1].y, ' ');
    } else {
        if (snake_len < MAX_SNAKE) snake_len++;
    }

    /* ---- Shift body ---- */
    for (i = snake_len - 1; i > 0; i--) {
        snake[i] = snake[i - 1];
    }
    snake[0] = new_head;

    /* ---- Draw updated snake ---- */
    draw_at(snake[0].x, snake[0].y, '@');   /* New head */
    if (snake_len > 1)
        draw_at(snake[1].x, snake[1].y, 'o'); /* Old head becomes body */

    /* ---- Place new food if eaten ---- */
    if (ate_food) place_food();
}

/* ============================================================
 *  Game Over Screen
 * ============================================================ */
static void show_game_over(void) {
    int row = FIELD_Y + FIELD_H / 2;
    int col = FIELD_X + FIELD_W / 2 - 8;

    uart_move_cursor(row,     col); uart_puts("+-----------------+");
    uart_move_cursor(row + 1, col); uart_puts("|   GAME  OVER!   |");
    uart_move_cursor(row + 2, col); uart_puts("|   Score: ");
    uart_print_int(score);
    uart_puts("       |");
    uart_move_cursor(row + 3, col); uart_puts("| Press R to retry|");
    uart_move_cursor(row + 4, col); uart_puts("+-----------------+");
    uart_show_cursor();
}

/* ============================================================
 *  main()  —  Entry Point
 * ============================================================ */
int main(void) {
    char c;

    uart_init();

    /* Welcome banner */
    uart_clear_screen();
    uart_move_cursor(5, 10);
    uart_puts("=========================================");
    uart_move_cursor(6, 10);
    uart_puts("  Welcome to RISC-V Snake!");
    uart_move_cursor(7, 10);
    uart_puts("  Running on YOUR custom RV32 CPU on FPGA");
    uart_move_cursor(8, 10);
    uart_puts("=========================================");
    uart_move_cursor(10, 10);
    uart_puts("  Controls: W/A/S/D to move, Q to quit");
    uart_move_cursor(12, 10);
    uart_puts("  Press any key to start...");

    /* Wait for keypress */
    uart_getc();

    /* Main game loop */
    while (1) {
        game_init();

        while (!game_over) {
            read_input();
            game_tick();
            if (!game_over)
                delay(TICK_DELAY);
        }

        show_game_over();

        /* Wait for R to retry or Q to quit */
        while (1) {
            c = uart_getc();
            if (c == 'r' || c == 'R') break;
            if (c == 'q' || c == 'Q') {
                uart_clear_screen();
                uart_move_cursor(5, 10);
                uart_puts("Thanks for playing! CPU powered off.");
                uart_newline();
                while(1); /* halt */
            }
        }
    }

    return 0;
}
