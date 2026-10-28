library ieee;
use ieee.std_logic_1164.all;

-- 480 x 320 单屏仪表盘布局。绘制器统一从这里取得坐标。
package ui_layout is
    constant SCREEN_W : natural := 480;
    constant SCREEN_H : natural := 320;

    constant HEADER_H : natural := 40;

    constant PREVIEW_X0 : natural := 12;
    constant PREVIEW_Y0 : natural := 48;
    constant PREVIEW_X1 : natural := 468;
    constant PREVIEW_Y1 : natural := 158;
    constant SPECTRUM_X0 : natural := 32;
    constant SPECTRUM_X1 : natural := 447;
    constant SPECTRUM_BOTTOM : natural := 140;

    constant LISSAJOUS_X0 : natural := 192;
    constant LISSAJOUS_X1 : natural := 287;
    constant LISSAJOUS_Y0 : natural := 56;
    constant LISSAJOUS_Y1 : natural := 151;

    constant TIMBRE_X0  : natural := 12;
    constant TIMBRE_Y0  : natural := 166;
    constant TIMBRE_X1  : natural := 232;
    constant TIMBRE_Y1  : natural := 206;

    constant VOLUME_X0  : natural := 248;
    constant VOLUME_Y0  : natural := 166;
    constant VOLUME_X1  : natural := 468;
    constant VOLUME_Y1  : natural := 206;

    constant ENVELOPE_X0 : natural := 12;
    constant ENVELOPE_Y0 : natural := 214;
    constant ENVELOPE_X1 : natural := 468;
    constant ENVELOPE_Y1 : natural := 260;

    constant EXPR_X0 : natural := 12;
    constant EXPR_Y0 : natural := 268;
    constant EXPR_X1 : natural := 468;
    constant EXPR_Y1 : natural := 312;

    constant BEND_X0   : natural := 12;
    constant BEND_X1   : natural := 115;
    constant VIB_X0    : natural := 121;
    constant VIB_X1    : natural := 224;
    constant GLIDE_X0  : natural := 230;
    constant GLIDE_X1  : natural := 333;
    constant EFFECT_X0 : natural := 339;
    constant EFFECT_X1 : natural := 468;

    function inside(x, y, x0, y0, x1, y1 : natural) return boolean;
end package;

package body ui_layout is
    function inside(x, y, x0, y0, x1, y1 : natural) return boolean is
    begin
        return x >= x0 and x <= x1 and y >= y0 and y <= y1;
    end function;
end package body;
