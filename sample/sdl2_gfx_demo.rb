#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick visual sanity check for SDL2_gfx primitives.
# Run: ruby sample/sdl2_gfx_demo.rb
#
# Press Q or Escape to quit.

require "teek"
require "teek/sdl2"

W = 800
H = 820

app = Teek::App.new
app.show
app.set_window_title("SDL2_gfx Demo")
app.set_window_geometry("#{W}x#{H}")

viewport = Teek::SDL2::Viewport.new(app, width: W, height: H)
viewport.pack(fill: :both, expand: true)

running = true
viewport.bind('KeyPress', :keysym) do |k|
  running = false if k == 'q' || k == 'Escape'
end

app.after(10) do
  animate = nil
  animate = proc do
    if running
      viewport.render do |r|
        r.clear(20, 20, 30)

        # === Row 1: Circles ===
        r.draw_circle(80, 70, 40, 255, 100, 100)
        r.fill_circle(200, 70, 40, 100, 255, 100)
        r.draw_aa_circle(320, 70, 40, 100, 100, 255)

        # === Row 1 right: AA lines (star) ===
        cx, cy = 520, 70
        8.times do |i|
          angle = i * Math::PI / 4
          x2 = cx + (45 * Math.cos(angle)).to_i
          y2 = cy + (45 * Math.sin(angle)).to_i
          r.draw_aa_line(cx, cy, x2, y2, 255, 255, 255)
        end

        # === Row 2: Ellipses ===
        r.draw_ellipse(80, 190, 55, 28, 255, 200, 0)
        r.fill_ellipse(220, 190, 55, 28, 200, 0, 255, 180)
        r.draw_aa_ellipse(370, 190, 55, 28, 0, 255, 200)

        # === Row 2 right: Thick lines ===
        r.draw_thick_line(480, 165, 620, 175, 1, 255, 255, 255)
        r.draw_thick_line(480, 185, 620, 195, 3, 255, 200, 100)
        r.draw_thick_line(480, 210, 620, 220, 6, 100, 200, 255)

        # === Row 3: Arcs & Pies ===
        r.draw_arc(80, 320, 45, 0, 270, 255, 150, 50)
        r.draw_pie(210, 320, 45, 30, 150, 50, 200, 255)
        r.fill_pie(340, 320, 45, 200, 340, 255, 100, 100)
        # Pac-Man
        r.fill_pie(480, 320, 45, 30, 330, 255, 255, 0)

        # === Row 4: Polygons ===
        # Pentagon outline
        n = 5
        px = n.times.map { |i| (80 + 40 * Math.cos(i * 2 * Math::PI / n - Math::PI / 2)).round }
        py = n.times.map { |i| (470 + 40 * Math.sin(i * 2 * Math::PI / n - Math::PI / 2)).round }
        r.draw_polygon(px, py, 100, 255, 200)

        # Filled hexagon
        n = 6
        hx = n.times.map { |i| (220 + 40 * Math.cos(i * 2 * Math::PI / n)).round }
        hy = n.times.map { |i| (470 + 40 * Math.sin(i * 2 * Math::PI / n)).round }
        r.fill_polygon(hx, hy, 200, 100, 255, 180)

        # AA polygon (diamond)
        r.draw_aa_polygon([360, 400, 360, 320], [430, 470, 510, 470], 255, 200, 100)

        # === Row 4 right: Bezier curves ===
        # Smooth S-curve
        r.draw_bezier(
          [470, 520, 580, 630, 680, 730],
          [440, 500, 440, 500, 440, 500],
          20, 255, 100, 255
        )
        # Looping curve
        r.draw_bezier(
          [470, 550, 650, 550, 730],
          [470, 430, 470, 510, 510],
          30, 100, 255, 150
        )

        # === Row 5: Semi-transparent overlaps ===
        r.fill_circle(150, 610, 50, 255, 50, 50, 140)
        r.fill_circle(200, 610, 50, 50, 50, 255, 140)
        r.fill_circle(175, 570, 50, 50, 255, 50, 140)

        # Filled pie chart
        r.fill_pie(450, 600, 55, 0, 120, 255, 100, 100)
        r.fill_pie(450, 600, 55, 120, 220, 100, 255, 100)
        r.fill_pie(450, 600, 55, 220, 360, 100, 100, 255)
        r.draw_aa_circle(450, 600, 55, 200, 200, 200)

        # === Row 6: Trigons ===
        r.draw_trigon(50, 780, 110, 700, 170, 780, 255, 200, 50)
        r.fill_trigon(200, 780, 260, 700, 320, 780, 50, 200, 255, 180)
        r.draw_aa_trigon(350, 780, 410, 700, 470, 780, 255, 100, 200)

        # === Row 6 right: pixel, hline, vline ===
        # Pixel grid
        8.times do |ix|
          8.times do |iy|
            c = ((ix + iy) % 2 == 0) ? 255 : 100
            r.draw_pixel(560 + ix * 4, 710 + iy * 4, c, c, 0)
          end
        end
        # H/V lines
        r.draw_hline(620, 750, 720, 255, 150, 50)
        r.draw_hline(620, 750, 740, 50, 150, 255)
        r.draw_vline(680, 700, 780, 150, 255, 50)
      end
      app.after(16) { animate.call }
    else
      app.command(:destroy, '.')
    end
  end
  animate.call
end

app.mainloop
