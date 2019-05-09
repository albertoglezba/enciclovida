class IUCNService

  attr_accessor :datos, :row, :validacion

  # Consulta la categoria de riesgo de un taxon dado
  def consultaRiesgo(opts)
    @iucn = CONFIG.iucn.api
    @token = CONFIG.iucn.token

    url = "#{@iucn}/api/v3/species/#{opts[:nombre].limpia_ws}?token=#{@token}"
    url_escape = URI.escape(url)
    uri = URI.parse(url_escape)
    req = Net::HTTP::Get.new(uri.to_s)
    begin
      res = Net::HTTP.start(uri.host, uri.port, :read_timeout => CONFIG.iucn.timeout ) {|http| http.request(req) }
      jres = JSON.parse(res.body)['result']
      jres[0]['category'] if jres.any?
    rescue => e
      nil
    end
  end

  # Guarda en cache la respuesta del servicio
  def dameRiesgo(opc={})
    resp = Rails.cache.fetch("iucn_#{opc[:id]}", expires_in: eval(CONFIG.cache.iucn)) do
      iucn = consultaRiesgo(opc)
      I18n.t("iucn_ws.#{iucn.estandariza}", :default => iucn) if iucn.present?
    end

    resp
  end

  # Accede al archivo que contiene los assessments y la taxonomia dentro de la carpeta versiones_IUCN
  # NOTAS: Este archivo se baja de la pagina de IUCN y hay que unir el archivo de asswessments con el de taxonomy
  def actualiza_IUCN(archivo)
    csv_path = Rails.root.join('public', 'IUCN', archivo)
    bitacora.puts 'Nombre científico en IUCN,Categoría en IUCN,Nombre en CAT,IdCAT,Estatus nombre,IdCAT válido,Nombre válido CAT,observaciones'
    return unless File.exists? csv_path

    CSV.foreach(csv_path, :headers => true) do |r|
      self.row = r
      self.datos = []
      self.datos[0] = row['scientificName']
      self.datos[1] = row['redlistCategory']

      v = Validacion.new
      v.nombre_cientifico = datos[0]
      v.encuentra_por_nombre
      self.validacion = v.validacion
      self.datos[7] = validacion[:msg]

      if validacion[:estatus]  # Hubo al menos una coincidencia
        if validacion[:taxon].present?  # Solo un resultado
          valida_extras
        end
      else
        if validacion[:taxones].present?  # Mas de un resultado
          cuantos_encontro = []

          validacion[:taxones].each do |taxon|
            validacion[:taxon] = taxon
            next unless misma_categoria?
            next unless mismo_reino?

            self.datos[2] = validacion[:taxon].nombre_cientifico
            self.datos[3] = validacion[:taxon].scat.catalogo_id
            self.datos[4] = validacion[:taxon].estatus

            next unless dame_el_valido
            cuantos_encontro << validacion[:taxon].id
          end

          cuantos_encontro.uniq!

          if cuantos_encontro.length == 1  # Caso mas sencillo de solo encontrar uno
            self.datos[7] = 'Búsqueda exacta'
          elsif cuantos_encontro.length > 1
            self.datos[2] = nil
            self.datos[3] = nil
            self.datos[4] = nil
            self.datos[5] = nil
            self.datos[6] = nil
            self.datos[7] = "[REVISAR] - Existe más de una coincidencia: #{validacion[:taxones].map{ |t| t.scat.catalogo_id }.join('|')}"
          else
            self.datos[7] = 'Sin coincidencias'
          end

        end
      end

      bitacora.puts datos.join(',')
    end

    bitacora.close
  end


  private

  # Bitacora especial para catalogos, antes de correr en real, pasarsela
  def bitacora
    log_path = Rails.root.join('log', Time.now.strftime('%Y-%m-%d_%H%m') + '_IUCN.csv')
    @@bitacora ||= File.new(log_path, 'a+')
  end

  # Valida que los reinos coincidan para evitar homonimos
  def mismo_reino?
    reino = validacion[:taxon].root.nombre_cientifico.estandariza

    if row['kingdomName'].estandariza == reino  # Si coincidio el reino y es un valido
      return true
    else  # Los reinos no coincidieron
      self.datos[7] = '[REVISAR] - Los reinos no coincidieron'
      return false
    end
  end

  # Comparo si la familia es la misma para busquedas similares
  def misma_familia?
    validacion[:taxon].asigna_categorias

    return true if validacion[:taxon].x_familia.estandariza == row['familyName'].estandariza

    self.datos[7] == 'Sin coincidencias'
    return false
  end

  # Valida que la categoria taxonomica sea la misma
  def misma_categoria?
    categorias = { 'subspecies' => 'subespecie', 'subspecies-plantae' => 'subespecie', 'variety' => 'variedad' }

    categoria = if row['infraType'].blank?
                  'especie'
                else
                  categorias[row['infraType'].estandariza]
                end

    cat_taxon = validacion[:taxon].categoria_taxonomica.nombre_categoria_taxonomica.estandariza

    unless cat_taxon == categoria
      self.datos[7] = '[REVISAR] - La categoria taxonómica no coincidio'
      return false
    end

    return true
  end

  # Asigna el nombre valido en caso de ser un sinonimo
  def dame_el_valido
    if validacion[:taxon].estatus == 1
      if taxon_valido = validacion[:taxon].dame_taxon_valido
        validacion[:taxon] = taxon_valido
        self.datos[5] = validacion[:taxon].scat.catalogo_id
        self.datos[6] = validacion[:taxon].nombre_cientifico
        self.datos[7] = 'Es un sinónimo y encontró el válido'
        return true
      else
        self.datos[5] = nil
        self.datos[6] = nil
        self.datos[7] = '[REVISAR] - Es un sinónimo y hubo problemas al encontrar el válido'
        return false
      end

    elsif validacion[:taxon].estatus == 2
      self.datos[5] = validacion[:taxon].scat.catalogo_id
      self.datos[6] = validacion[:taxon].nombre_cientifico
      return true
    end
  end

  # Valida el nombre y categoría taxonomica
  def valida_extras
    self.datos[7] = validacion[:msg]

    if datos[7] = 'Búsqueda similar'
      self.datos[7] = '[REVISAR] - Búsqueda similar'
      return unless misma_familia?
    end

    self.datos[2] = validacion[:taxon].nombre_cientifico
    self.datos[3] = validacion[:taxon].scat.catalogo_id
    self.datos[4] = validacion[:taxon].estatus

    return unless mismo_reino?
    return unless dame_el_valido

    misma_categoria?
  end

end

