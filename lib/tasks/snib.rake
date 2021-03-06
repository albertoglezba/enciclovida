namespace :snib do

  # Namespace para las especies
  namespace :especies do
    desc "Genera/actualiza las especies por estado de la base del SNIB y lo guarda en cache"
    task estado: :environment do
      Geoportal::Estado.all.select(:region_id).each do |estado|
        Rails.logger.info "[DEBUG] - Generando cache de especies con estado: #{estado.region_id}"
        geo = Geoportal::Snib.new
        geo.params = { region_id: estado.region_id, tipo_region: 'estado' }
        geo.borra_cache_especies
        geo.especies
      end

      Rails.logger.info "[DEBUG] - Generando cache de especies a nivel de estado"
      geo = Geoportal::Snib.new
      geo.params = { tipo_region: 'estado' }
      geo.borra_cache_especies
      geo.especies
    end

    desc "Genera/actualiza las especies por municipio de la base del SNIB y lo guarda en cache"
    task municipio: :environment do
      Geoportal::Municipio.all.select(:region_id).each do |municipio|
        Rails.logger.info "[DEBUG] - Generando cache de especies con municipio: #{municipio.region_id}"
        geo = Geoportal::Snib.new
        geo.params = { region_id: municipio.region_id, tipo_region: 'municipio' }
        geo.borra_cache_especies
        geo.especies
      end

      Rails.logger.info "[DEBUG] - Generando cache de especies a nivel de municipio"
      geo = Geoportal::Snib.new
      geo.params = { tipo_region: 'municipio' }
      geo.borra_cache_especies
      geo.especies
    end

    desc "Genera/actualiza las especies por ANP de la base del SNIB y lo guarda en cache"
    task anp: :environment do
      Geoportal::Anp.all.select(:region_id).each do |anp|
        Rails.logger.info "[DEBUG] - Generando cache de especies con ANP: #{anp.region_id}"
        geo = Geoportal::Snib.new
        geo.params = { region_id: anp.region_id, tipo_region: 'anp' }
        geo.borra_cache_especies
        geo.especies
      end

      Rails.logger.info "[DEBUG] - Generando cache de especies a nivel de anp"
      geo = Geoportal::Snib.new
      geo.params = { tipo_region: 'anp' }
      geo.borra_cache_especies
      geo.especies
    end

    desc "Genera/actualiza las especies por estado, municipio y ANP de la base del SNIB y lo guarda en cache"
    task todos: :environment do
      regiones = %w(default estado municipio anp)
      
      regiones.each do |region|
        if region == 'default'
          # El cache de todas las especies a nivel nacional, i.e. sin tipo_region ni region_id
          Rails.logger.info "[DEBUG] - Generando cache de especies a nivel nacional"
          geo = Geoportal::Snib.new
          geo.params = {}
          geo.borra_cache_especies
          geo.especies
        else
          "Geoportal::#{region.camelize}".constantize.all.each do |reg|
            Rails.logger.info "[DEBUG] - Generando cache de especies con #{region.camelize}: #{reg.region_id}"
            geo = Geoportal::Snib.new
            geo.params = { region_id: reg.region_id, tipo_region: region }
            geo.borra_cache_especies
            geo.especies
          end

          Rails.logger.info "[DEBUG] - Generando cache de especies a nivel: #{region}"
          geo = Geoportal::Snib.new
          geo.params = { tipo_region: region }
          geo.borra_cache_especies
          geo.especies
        end
      end
    end  # End task todos

  end

  # Namespace para los registros
  namespace :registros do
    desc "Genera/actualiza los registros default por especie, cuando no selecciono ningun tipo_region y lo guarda en cache"
    task default: :environment do
      Geoportal::Snib.all.select(:idnombrecatvalido).group(:idnombrecatvalido).map(&:idnombrecatvalido).each do |idnombrecatvalido|
        Rails.logger.info "[DEBUG] - Generando cache para: #{idnombrecatvalido}"
        geo = Geoportal::Snib.new
        geo.params = { catalogo_id: idnombrecatvalido }
        geo.borra_cache_ejemplares
        geo.ejemplares
      end
    end

    desc "Genera/actualiza los registros cuando se tiene tipo_region estado"
    task estado: :environment do
      Geoportal::Snib.all.select(:idnombrecatvalido).where("entid IS NOT NULL").group(:idnombrecatvalido).map(&:idnombrecatvalido).each do |idnombrecatvalido|
        Rails.logger.info "[DEBUG] - Generando cache para: #{idnombrecatvalido}"
        geo = Geoportal::Snib.new
        geo.params = { catalogo_id: idnombrecatvalido, tipo_region: 'estado' }
        geo.borra_cache_ejemplares
        geo.ejemplares
      end
    end

    desc "Genera/actualiza los registros cuando se tiene tipo_region municipio"
    task municipio: :environment do
      Geoportal::Snib.all.select(:idnombrecatvalido).where("munid IS NOT NULL").group(:idnombrecatvalido).map(&:idnombrecatvalido).each do |idnombrecatvalido|
        Rails.logger.info "[DEBUG] - Generando cache para: #{idnombrecatvalido}"
        geo = Geoportal::Snib.new
        geo.params = { catalogo_id: idnombrecatvalido, tipo_region: 'municipio' }
        geo.borra_cache_ejemplares
        geo.ejemplares
      end
    end

    desc "Genera/actualiza los registros cuando se tiene tipo_region ANP"
    task anp: :environment do
      Geoportal::Snib.all.select(:idnombrecatvalido).where("anpid IS NOT NULL").group(:idnombrecatvalido).map(&:idnombrecatvalido).each do |idnombrecatvalido|
        Rails.logger.info "[DEBUG] - Generando cache para: #{idnombrecatvalido}"
        geo = Geoportal::Snib.new
        geo.params = { catalogo_id: idnombrecatvalido, tipo_region: 'anp' }
        geo.borra_cache_ejemplares
        geo.ejemplares
      end
    end    

    desc "Genera/actualiza los registros que se tienen para default, estado, municipio y ANP"
    task todos: :environment do
      tipos_regiones = { 'default' => '', 'estado' => 'entid', 'municipio' => 'munid', 'anp' => 'anpid' }
      
        tipos_regiones.each do |tipo_region, campo|
          Rails.logger.info "[DEBUG] - Generando cache para tipo_region: #{tipo_region}"
          geoportal = Geoportal::Snib.all.select(:idnombrecatvalido).group(:idnombrecatvalido)
          geoportal = geoportal.where("#{campo} IS NOT NULL") if campo.present?
          
          geoportal.map(&:idnombrecatvalido).each do |idnombrecatvalido|
            Rails.logger.info "[DEBUG] - Generando cache para: #{idnombrecatvalido}"
            geo = Geoportal::Snib.new

            if tipo_region == 'default'
              geo.params = { catalogo_id: idnombrecatvalido }
            else
              geo.params = { catalogo_id: idnombrecatvalido, tipo_region: tipo_region }
            end
            
            geo.borra_cache_ejemplares
            geo.ejemplares
          end
        end
    end
  end

end
