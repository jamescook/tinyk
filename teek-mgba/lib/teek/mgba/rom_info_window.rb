# frozen_string_literal: true

require_relative "child_window"
require_relative "locale"

module Teek
  module MGBA
    # Displays ROM metadata in a read-only window.
    #
    # Shown via View > ROM Info when a ROM is loaded. Contains a two-column
    # grid of labels: field name on the left, value on the right.
    class RomInfoWindow
      include ChildWindow
      include Locale::Translatable

      TOP = ".mgba_rom_info"

      # GBA maker/publisher codes (2-char ASCII → publisher name).
      # Source: various community-maintained databases of GBA ROM headers.
      MAKER_CODES = {
        '01' => 'Nintendo',
        '08' => 'Capcom',
        '13' => 'Electronic Arts Japan',
        '18' => 'Hudson Soft',
        '20' => 'Destination Software / Zoo Digital',
        '24' => 'PCM Complete',
        '25' => 'San-X',
        '28' => 'Kemco Japan',
        '29' => 'SETA Corporation',
        '2N' => 'Nowpro',
        '30' => 'Viacom / Infogrames',
        '34' => 'Konami',
        '35' => 'Hector',
        '36' => 'Codemasters',
        '37' => 'GAGA Communications',
        '38' => 'Laguna',
        '41' => 'Ubisoft',
        '42' => 'Sunsoft',
        '47' => 'Spectrum Holobyte',
        '49' => 'IREM',
        '4D' => 'Malibu Games',
        '4F' => 'Eidos / U.S. Gold',
        '4Q' => 'Disney',
        '4Z' => 'Crave Entertainment',
        '50' => 'Absolute Entertainment',
        '51' => 'Acclaim',
        '52' => 'Activision',
        '54' => 'GameTek',
        '56' => 'LJN',
        '58' => 'Mattel',
        '5D' => 'Midway / Tradewest',
        '5G' => 'Majesco',
        '5H' => '3DO',
        '5L' => 'NewKidCo',
        '5S' => 'TDK Mediactive',
        '60' => 'Titus',
        '61' => 'Virgin',
        '64' => 'LucasArts',
        '67' => 'Ocean',
        '69' => 'Electronic Arts',
        '6E' => 'Elite Systems',
        '6F' => 'Electro Brain',
        '6L' => 'BAM! Entertainment',
        '6S' => 'TDK Mediactive',
        '70' => 'Infogrames',
        '71' => 'Interplay',
        '72' => 'JVC / Broderbund',
        '73' => 'Sculptured Software',
        '75' => 'The Sales Curve / SCi',
        '78' => 'THQ',
        '79' => 'Accolade',
        '7A' => 'Triffix',
        '7D' => 'Sierra / Universal Interactive',
        '7F' => 'Kemco',
        '7G' => 'Rage Software',
        '7H' => 'Encore',
        '7L' => 'Warped Productions',
        '80' => 'Misawa',
        '83' => 'LOZC / G.Amusements',
        '86' => 'Tokuma Shoten',
        '87' => 'Tsukuda Original',
        '8B' => 'Bullet-Proof Software',
        '8C' => 'Vic Tokai',
        '8E' => 'Character Soft',
        '8J' => 'General Entertainment',
        '8N' => 'Success',
        '91' => 'Chunsoft',
        '92' => 'Video System',
        '93' => 'BEC / Ocean / Acclaim',
        '95' => 'Varie',
        '97' => 'Kaneko',
        '99' => 'Pack-In-Video',
        '9B' => 'Tecmo',
        '9C' => 'Imagineer',
        '9H' => 'Bottom Up',
        'A0' => 'Telenet',
        'A1' => 'Hori',
        'A4' => 'Konami',
        'A7' => 'Takara',
        'A9' => 'Technos Japan',
        'AA' => 'JVC / Broderbund',
        'AC' => 'Toei Animation',
        'AD' => 'Toho',
        'AF' => 'Namco',
        'AG' => 'Media Rings',
        'AH' => 'J-Wing',
        'AK' => 'KID',
        'AL' => 'MediaFactory',
        'AP' => 'Infogrames Hudson',
        'AQ' => 'Kiratto Ludic',
        'AY' => 'Yacht Club Games',
        'B0' => 'Acclaim Japan / Nexsoft',
        'B1' => 'ASCII / Nexsoft',
        'B2' => 'Bandai',
        'B4' => 'Enix',
        'B6' => 'HAL Laboratory',
        'B7' => 'SNK',
        'B9' => 'Pony Canyon',
        'BA' => 'Culture Brain',
        'BB' => 'Sunsoft',
        'BD' => 'Sony Imagesoft',
        'BF' => 'Sammy',
        'BG' => 'Magical',
        'BJ' => 'Compile',
        'BL' => 'MTO',
        'BN' => 'Sunrise Interactive',
        'BP' => 'Global A Entertainment',
        'C0' => 'Taito',
        'C2' => 'Kemco',
        'C3' => 'Square Soft',
        'C4' => 'Tokuma Shoten',
        'C5' => 'Data East',
        'C6' => 'Tonkin House',
        'C8' => 'Koei',
        'CB' => 'Vap',
        'CC' => 'Use Corporation',
        'CD' => 'Meldac',
        'CE' => 'Pony Canyon / FCI',
        'CF' => 'Angel / Dtop',
        'CG' => 'Marvelous Entertainment',
        'CJ' => 'Boss Communication',
        'CK' => 'Axela / Crea-Tech',
        'CP' => 'Enterbrain',
        'D0' => 'Taito',
        'D1' => 'Sofel',
        'D2' => 'Quest',
        'D3' => 'Sigma Enterprises',
        'D4' => 'Ask Kodansha',
        'D6' => 'Naxat Soft',
        'D7' => 'Copya System',
        'D9' => 'Banpresto',
        'DA' => 'Tomy',
        'DB' => 'LJN Japan',
        'DD' => 'NCS',
        'DE' => 'Human',
        'DF' => 'Altron',
        'DH' => 'Gaps',
        'DK' => 'Kodansha',
        'DN' => 'ELF',
        'E2' => 'Yutaka',
        'E3' => 'Varie',
        'E5' => 'Epoch',
        'E7' => 'Athena',
        'E8' => 'Asmik / Asmik Ace',
        'E9' => 'Natsume',
        'EB' => 'Atlus',
        'EC' => 'Epic / Sony Records',
        'EE' => 'IGS',
        'EL' => 'Spike',
        'EM' => 'Konami Computer Entertainment Tokyo',
        'EP' => 'Sting',
        'ES' => 'Square Enix',
        'F0' => 'A-Wave',
        'G1' => 'PCCW',
        'G4' => 'KiKi',
        'G5' => 'Open Sesame',
        'G6' => 'Sims',
        'G7' => 'Broccoli',
        'G8' => 'Avex',
        'G9' => 'D3 Publisher',
        'GB' => 'Konami Computer Entertainment Japan',
        'GD' => 'Square Enix',
        'GE' => 'KSG',
        'GF' => 'Micott & Basara',
        'GH' => 'Orbital Media',
        'GN' => 'Nintendo',
        'GT' => '505 Games',
        'GY' => 'The Game Factory',
        'H1' => 'Treasure',
        'H2' => 'Aruze',
        'H3' => 'Ertain',
        'H4' => 'SNK Playmore',
        'HF' => 'Level-5',
        'HJ' => 'Genius Sonority',
        'HY' => 'Reef Entertainment',
        'IH' => 'Yojigen',
        'J9' => 'AQ Interactive',
        'JF' => 'Arc System Works',
        'K6' => 'Nihon System',
        'KB' => 'NexEntertainment',
        'KM' => 'Cybird',
        'KP' => 'Purple Hills',
        'LH' => 'Sekai Project',
        'LP' => 'Witchcraft',
        'LT' => 'Inti Creates',
        'LU' => 'XSEED Games',
        'MJ' => 'MumboJumbo',
        'MR' => 'Mindscape',
        'MS' => 'Mindscape / Red Orb',
        'MT' => 'Blast!',
        'N9' => 'Teyon',
        'NK' => 'Neko Entertainment',
        'NP' => 'Nobilis',
        'PL' => 'Playlogic',
        'RA' => 'Nordcurrent',
        'RS' => 'Warner Bros. Interactive',
        'SU' => 'Slitherine',
        'SV' => 'SevenOne Intermedia / dtp',
        'TR' => 'Tetris Online',
        'UG' => 'Metro3D / Data Design',
        'VN' => 'GameFly',
        'VP' => 'Virgin Play',
        'VZ' => 'Little Orbit',
        'WR' => 'Warner Bros. Interactive',
        'XJ' => 'XSEED Games',
        'XS' => 'Aksys Games',
        'YT' => 'Valcon Games',
        'Z4' => 'Ntreev Soft',
        'ZA' => 'WBA Interactive',
        'ZH' => 'Internal Engine',
        'ZS' => 'Zinkia',
        'ZW' => 'Judo Baby',
        'ZX' => 'TopWare Interactive',
      }.freeze

      # Look up a publisher name from a 2-char maker code.
      # @param code [String] 2-character maker code
      # @return [String] publisher name, or "Unknown (XX)"
      def self.publisher_name(code)
        MAKER_CODES[code] || "Unknown (#{code})"
      end

      def initialize(app, callbacks: {})
        @app = app
        @callbacks = callbacks
        @built = false
      end

      # Show the ROM Info window, populating it with data from the given core.
      # @param core [Teek::MGBA::Core]
      # @param rom_path [String] path to the ROM file
      # @param save_path [String] path to the .sav file
      def show(core, rom_path:, save_path:)
        build_ui unless @built
        populate(core, rom_path, save_path)
        show_window(modal: false)
      end

      def hide
        hide_window(modal: false)
      end

      private

      def build_ui
        build_toplevel(translate('rom_info.title')) do
          build_fields
        end
        @built = true
      end

      def build_fields
        frame = "#{TOP}.f"
        @app.command('ttk::frame', frame, padding: 12)
        @app.command(:pack, frame, fill: :both, expand: 1)

        @fields = {}
        rows = %w[title game_code publisher platform rom_size checksum
                   rom_path save_path resolution]
        labels = {
          'title'      => translate('rom_info.field_title'),
          'game_code'  => translate('rom_info.game_code'),
          'publisher'  => translate('rom_info.publisher'),
          'platform'   => translate('rom_info.platform'),
          'rom_size'   => translate('rom_info.rom_size'),
          'checksum'   => translate('rom_info.checksum'),
          'rom_path'   => translate('rom_info.rom_file'),
          'save_path'  => translate('rom_info.save_file'),
          'resolution' => translate('rom_info.resolution'),
        }

        rows.each_with_index do |key, i|
          lbl = "#{frame}.lbl_#{key}"
          val = "#{frame}.val_#{key}"

          @app.command('ttk::label', lbl, text: labels[key], anchor: :e, width: 12)
          @app.command(:grid, lbl, row: i, column: 0, sticky: :e, padx: [0, 8], pady: 3)

          @app.command('ttk::label', val, text: '', anchor: :w)
          @app.command(:grid, val, row: i, column: 1, sticky: :w, pady: 3)

          @fields[key] = val
        end

        # Close button
        btn = "#{frame}.close_btn"
        @app.command('ttk::button', btn, text: translate('rom_info.close'), command: proc { hide })
        @app.command(:grid, btn, row: rows.size, column: 0, columnspan: 2, pady: [12, 0])
      end

      def populate(core, rom_path, save_path)
        set_field('title', core.title)

        game_code = core.game_code
        set_field('game_code', game_code)

        maker = core.maker_code
        na = translate('rom_info.na')
        publisher = maker.empty? ? na : "#{self.class.publisher_name(maker)} (#{maker})"
        set_field('publisher', publisher)

        set_field('platform', core.platform)
        set_field('rom_size', format_size(core.rom_size))
        set_field('checksum', "0x%08X" % core.checksum)
        set_field('rom_path', rom_path || na)
        set_field('save_path', save_path || na)
        set_field('resolution', "#{core.width}x#{core.height}")

        @app.command(:wm, 'title', TOP, "#{translate('rom_info.title')} \u2014 #{core.title}")
      end

      def set_field(key, value)
        widget = @fields[key]
        @app.command(widget, 'configure', text: value.to_s) if widget
      end

      def format_size(bytes)
        if bytes >= 1024 * 1024
          "%.1f MB (%d bytes)" % [bytes / (1024.0 * 1024), bytes]
        elsif bytes >= 1024
          "%.1f KB (%d bytes)" % [bytes / 1024.0, bytes]
        else
          "#{bytes} bytes"
        end
      end
    end
  end
end
