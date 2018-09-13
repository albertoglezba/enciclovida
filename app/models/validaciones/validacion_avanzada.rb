class ValidacionAvanzada < Validacion

  attr_accessor :fila

  # Si alguna columna se llama diferente, es solo cosa de añadir un elemento mas al array correspondiente
  COLUMNAS_OPCIONALES = {reino: ['reino'], division: ['division'], subdivision: ['subdivision'], clase: ['clase'], subclase: ['subclase'],
                         orden: ['orden'], suborden: ['suborden'], infraorden: ['infraorden'], superfamilia: ['superfamilia'],
                         subgenero: ['subgenero'], nombre_autoridad_infraespecie: %w(nombre_autoridad_infraespecie autoridad_infraespecie)}
  COLUMNAS_OBLIGATORIAS = {familia: ['familia'], genero: ['genero'], especie: ['especie'], nombre_autoridad: %w(nombre_autoridad autoridad),
                           infraespecie: ['infraespecie'], categoria_taxonomica: %w(categoria categoria_taxonomica), nombre_cientifico: ['nombre_cientifico']}

  # Colores de las secciones en la validacion
  RESUMEN = '00BFFF'
  CORRECCIONES = 'FF8C00'
  VALIDACION_INTERNA = '32CD32'
  INFORMACION_ORIG = 'C9C9C9'

  def initialize
    self.fila = {}
    super
  end

  def valida_archivo
    super

    sheet.parse(cabecera).each_with_index do |f, index|
      self.fila = f
      self.nombre_cientifico = f['nombre_cientifico']

      if nombre_cientifico.blank?
        self.validacion[:estatus] = false
        self.validacion[:msg] = 'El nombre cientifico esta vacio.'
        self.recurso_validado << asocia_respuesta
        next
      end

      encuentra_por_nombre

      if validacion[:estatus]  # Encontro solo un nombre cientifico
        validacion[:taxon].asigna_categorias
      else # No encontro coincidencias, tratamos mas arriba
        if validacion[:taxones].present? && validacion[:taxones].any?
          quita_sinonimos_coincidencias
          busca_recursivamente unless validacion[:estatus]
        else  # Este caso regreso sin coincidencias, es forzoso validar mas arriba
          valida_mas_arriba
        end
      end  # info estatus inicial

      self.recurso_validado << asocia_respuesta  # Asocia cuanquier resultado
    end  # sheet parse

    resp = escribe_excel

    if resp[:estatus]
      self.excel_url = resp[:excel_url]
      EnviaCorreo.excel(self).deliver
    end
  end

  # Valida en genero, familia u orden
  def valida_mas_arriba
    puts "\n\nValida mas arriba de especie ..."
    # Las interseccion de categorias validas entre el excel y las permitidas
    categorias = (CategoriaTaxonomica::CATEGORIAS & fila.keys).reverse
    asegurar_categoria = %w(genero familia orden)  # Solo estas categorias se sube a validar

    categorias.each do |categoria|
      next unless fila[categoria].present?
      next unless asegurar_categoria.include?(categoria)
      puts "\n Tratando de encontrar mas arriba con: #{categoria}"

      # Asigna una categoria mas arriba a nombre cientifico
      self.nombre_cientifico = fila[categoria]
      encuentra_por_nombre

      if validacion[:estatus]  # Encontro un unico nombe valido
        validacion[:taxon].asigna_categorias

        # Compara que la categoria taxonomica de la coincidencia sea la misma que la categoria que del ciclo
        if I18n.transliterate(validacion[:taxon].x_categoria_taxonomica).gsub(' ','_').downcase.strip == categoria
          validacion[:msg] = "valido hasta #{validacion[:taxon].x_categoria_taxonomica}"
          validacion[:valido_hasta] = true
          break
        else
          self.validacion[:estatus] = false
          next
        end
      end
    end

    # Por si no hubo ningun valido o encontro mas de uno, eso en automatico es sin coincidencias
    if !validacion[:estatus]
      validacion[:msg] = 'Sin coincidencias'
    end
  end

  # Busca recursivamente el indicado, si entro aqui es porque hay mas de un resultado
  def busca_recursivamente
    puts "\n\nBusca recursivamente ..."
    validacion[:taxones].each do |taxon|

      taxon.asigna_categorias  # Completa la informacion del taxon
      validacion[:taxon] = taxon
      coincide_familia_orden?

      if validacion[:estatus]  # Puede que se quede con el primer caso que coincida la familia o el orden
        validacion[:msg] = 'Búsqueda similar'
        return
      end
    end
  end

  # Asocia la respuesta para armar el contenido del excel
  def asocia_respuesta
    puts "\n\nAsocia la respuesta con el excel"
    if validacion[:estatus]
      taxon_estatus
    end

    if validacion[:taxon_valido].present?
      self.validacion[:taxon] = validacion[:taxon_valido]
      self.validacion[:taxon].asigna_categorias
    end

    # Devuelve toda la asociacion unidas y en orden
    { resumen: resumen, correcciones: correcciones, validacion_interna: validacion_interna }
  end

  def escribe_excel
    puts "\n\nEscribe el excel ..."
    fila = 1  # Empezamos por la cabecera
    xlsx = RubyXL::Parser.parse(archivo_copia)  # El excel con su primera sheet
    sheet_p = xlsx[0]

    recurso_validado.each do |h|
      columna = sheet.last_column  # Desde la columna donde termina su informacion

      h.each do |seccion,datos|
        datos.each do |campo, dato|
          # Para la cabecera, asigna tambien el color correspondiente, de acuerdo a la seccion
          sheet_p.add_cell(0,columna,campo).change_fill(eval(seccion.to_s.upcase)) if fila == 1

          # Para los datos abajo de la cabecera
          if dato.class == String
            begin  # Revisar posteriormente esta linea, por si no tiene nombre cientifico
              sheet_p.add_cell(fila,columna,dato)
            rescue
              puts "@@@#{dato.inspect}"
            end
          elsif dato.class == Hash  # Es la cabecera
            sheet_p.add_cell(fila,columna,dato[:valor]).change_fill(dato[:color])
          elsif dato.class == Array  # Es de la validación de conabio y tiene un datos desl usuario original
            sheet_p.add_cell(fila,columna,dato[0]).change_fill(dato[1])
          end

          columna+= 1
        end
      end

      fila+= 1
    end

    # Escribe el excel en cierta ruta
    fecha = Time.now.strftime("%Y-%m-%d")
    ruta_dir = Rails.root.join('public','descargas_resultados', fecha)
    nombre_archivo = Time.now.strftime("%Y-%m-%d_%H-%M-%S-%L") + '_taxa_EncicloVida.xlsx'
    FileUtils.mkpath(ruta_dir, :mode => 0755) unless File.exists?(ruta_dir)
    ruta_excel = ruta_dir.join(nombre_archivo)
    xlsx.write(ruta_excel)

    if File.exists? ruta_excel
      excel_url = "#{CONFIG.site_url}descargas_resultados/#{fecha}/#{nombre_archivo}"
      {estatus: true, excel_url: excel_url}
    else
      {estatus: true, msg: 'No pudo guardar el archivo'}
    end
  end

  def coincide_familia_orden?  # Valida si coincide con la familia o el orden, en este punto ya tengo un taxon candidato
    taxon = validacion[:taxon]

    # Si no esta puesta la familia en el taxon que coincide, entonces quiere decir que ya subio hasta familia y no es igual, entonces no hubo coincidencias
    if taxon.x_familia.blank?
      validacion[:estatus] = false
      validacion[:msg] = 'Sin coincidencias'
      validacion[:salir] = true
      return
    end

    if fila['familia'].present?  # Si escribio la familia en el excel entonces debe de coincidir
      if fila['familia'].downcase.strip == taxon.x_familia.downcase.strip
        validacion[:estatus] = true
      else
        validacion[:estatus] = false
        validacion[:msg] = "No coincidio la famila - Orig: #{fila['familia']}; Enciclo: #{taxon.x_familia}"
        validacion[:salir] = true
      end
    elsif fila['orden'].present?  # Si escribio el orden
      if fila['orden'].downcase.strip == taxon.x_orden.downcase.strip
        validacion[:estatus] = true
      else
        validacion[:estatus] = false
        validacion[:msg] = "No coincidio el orden - Orig: #{fila['orden']}; Enciclo: #{taxon.x_orden}"
        validacion[:salir] = true
      end
    else  # No tiene ni familia ni orden, entonces lo regreso false, ya que es ambiguo y no se puede decidir
      validacion[:estatus] = false
      validacion[:msg] = 'Sin coincidencias'
    end

    puts "\n\n\nResultado en familia u orden: #{validacion[:estatus].to_s}"
  end

  private

  # Parte roja del excel
  def resumen
    resumen_hash = {}
    columnas = %w(SCAT_NombreEstatus SCAT_Observaciones SCAT_Correccion_NombreCient SCAT_NombreCient_valido SCAT_Autoridad_NombreCient_valido)

    if validacion[:estatus]
      taxon = validacion[:taxon]

      if validacion[:taxon_valido].present?
        resumen_hash['SCAT_NombreEstatus'] = 'sinónimo'
      else
        resumen_hash['SCAT_NombreEstatus'] = Especie::ESTATUS_SIGNIFICADO[taxon.estatus]
      end

      resumen_hash['SCAT_Observaciones'] = validacion[:msg]

      if validacion[:valido_hasta].present?
        resumen_hash['SCAT_Correccion_NombreCient'] = nil
      else
        resumen_hash['SCAT_Correccion_NombreCient'] = taxon.nombre_cientifico.downcase == fila['nombre_cientifico'].downcase ? nil : taxon.nombre_cientifico
      end

      resumen_hash['SCAT_NombreCient_valido'] = taxon.nombre_cientifico
      resumen_hash['SCAT_Autoridad_NombreCient_valido'] = taxon.nombre_autoridad

    else  # Asociacion vacia, solo el error
      columnas.each do |columna|
        if columna == 'SCAT_Observaciones' && validacion[:msg].present?
          resumen_hash[columna] = validacion[:msg]
        else
          resumen_hash[columna] = nil
        end
      end
    end

    resumen_hash
  end

  # Parte azul del excel
  def correcciones
    puts "\n\nGenerando informacion de correcciones ..."
    correcciones_hash = {}
    taxon = validacion[:taxon]

    # Se iteran con los campos que previamente coincidieron en compruebas_columnas
    fila.each do |campo, valor|
      if validacion[:estatus]
        if campo == 'infraespecie'  # caso especial para las infrespecies
          begin
            cat = I18n.transliterate(taxon.x_categoria_taxonomica).gsub(' ','_').downcase.strip
          rescue  # Por si la infraespcie es vacia cuando completo el taxon
            cat = ''
          end

          if CategoriaTaxonomica::CATEGORIAS_INFRAESPECIES.include?(cat)
            correcciones_hash["SCAT_Correccion#{campo.capitalize}"] = taxon.nombre.downcase == fila[campo].try(:downcase) ? nil : taxon.nombre
          else
            correcciones_hash["SCAT_Correccion#{campo.capitalize}"] = nil
          end

        else
          correcciones_hash["SCAT_Correccion#{campo.capitalize}"] = eval("taxon.x_#{campo}").try(:downcase) == fila[campo].try(:downcase) ? nil : eval("taxon.x_#{campo}")
        end

      else
        correcciones_hash["SCAT_Correccion#{campo.capitalize}"] = nil
      end
    end

    correcciones_hash
  end

  # La validacion en comun, no importa si es simple o avanzada
  def validacion_interna
    validacion_interna_hash = {}
    columnas = %w(SCAT_Reino_valido SCAT_Phylum-Division_valido SCAT_Clase_valido SCAT_Subclase_valido SCAT_Orden_valido SCAT_Suborden_valido SCAT_Infraorden_valido SCAT_Superfamilia_valido SCAT_Familia_valido SCAT_Genero_valido SCAT_Subgenero_valido SCAT_Especie_valido SCAT_AutorEspecie_valido SCAT_Infraespecie_valido SCAT_Categoria_valido SCAT_AutorInfraespecie_valido SCAT_NombreCient_valido SCAT_NOM-059 SCAT_IUCN SCAT_CITES SCAT_Distribucion SCAT_CatalogoDiccionario SCAT_Fuente ENCICLOVIDA)

    if validacion[:estatus]
      taxon = validacion[:taxon]

      validacion_interna_hash['SCAT_Reino_valido'] = taxon.x_reino || (fila['Reino'].present? ? [fila['Reino'],INFORMACION_ORIG] : '')

      if taxon.x_phylum.present?
        validacion_interna_hash['SCAT_Phylum/Division_valido'] = taxon.x_phylum || [fila['division'], INFORMACION_ORIG] || [fila['phylum'], INFORMACION_ORIG]
      else
        validacion_interna_hash['SCAT_Phylum/Division_valido'] = taxon.x_division || [fila['division'], INFORMACION_ORIG] || [fila['phylum'], INFORMACION_ORIG]
      end

      validacion_interna_hash['SCAT_Clase_valido'] = taxon.x_clase || (fila['clase'].present? ? [fila['clase'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Subclase_valido'] = taxon.x_subclase || (fila['subclase'].present? ? [fila['subclase'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Orden_valido'] = taxon.x_orden || (fila['orden'].present? ? [fila['orden'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Suborden_valido'] = taxon.x_suborden || (fila['suborden'].present? ? [fila['suborden'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Infraorden_valido'] = taxon.x_infraorden || (fila['infraorden'].present? ? [fila['infraorden'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Superfamilia_valido'] = taxon.x_superfamilia || (fila['superfamilia'].present? ? [fila['superfamilia'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Familia_valido'] = taxon.x_familia || (fila['familia'].present? ? [fila['familia'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Genero_valido'] = taxon.x_genero || (fila['genero'].present? ? [fila['genero'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Subgenero_valido'] = taxon.x_subgenero || (fila['subgenero'].present? ? [fila['subgenero'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_Especie_valido'] = taxon.x_especie || (fila['especie'].present? ? [fila['especie'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_AutorEspecie_valido'] = taxon.x_nombre_autoridad || (fila['nombre_autoridad'].present? ? [fila['nombre_autoridad'], INFORMACION_ORIG] : '')

      # Para la infraespecie
      begin
        cat = I18n.transliterate(taxon.x_categoria_taxonomica).gsub(' ','_').downcase.strip
      rescue  # Por si la infraespcie es vacia cuando completo el taxon
        cat = ''
      end

      if CategoriaTaxonomica::CATEGORIAS_INFRAESPECIES.include?(cat)
        validacion_interna_hash['SCAT_Infraespecie_valido'] = taxon.nombre || (fila['infraespecie'].present? ? [fila['infraespecie'], INFORMACION_ORIG] : '')
      else
        validacion_interna_hash['SCAT_Infraespecie_valido'] = fila['infraespecie'].present? ? [fila['infraespecie'], INFORMACION_ORIG] : ''
      end

      validacion_interna_hash['SCAT_Categoria_valido'] = taxon.x_categoria_taxonomica || (fila['categoria_taxonomica'].present? ? [fila['categoria_taxonomica'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_AutorInfraespecie_valido'] = taxon.x_nombre_autoridad_infraespecie || (fila['nombre_autoridad_infraespecie'].present? ? [fila['nombre_autoridad_infraespecie'], INFORMACION_ORIG] : '')
      validacion_interna_hash['SCAT_NombreCient_valido'] = taxon.nombre_cientifico

      # Para la NOM
      #nom = taxon.estados_conservacion.where('nivel1=4 AND nivel2=1 AND nivel3>0').distinct
      nom = taxon.catalogos.nom
      if nom.length == 1
        taxon.x_nom = nom[0].descripcion
        validacion_interna_hash['SCAT_NOM-059'] = taxon.x_nom
      else
        validacion_interna_hash['SCAT_NOM-059'] = nil
      end

      # Para IUCN
      #iucn = taxon.estados_conservacion.where('nivel1=4 AND nivel2=2 AND nivel3>0').distinct
      iucn = taxon.catalogos.iucn
      if iucn.length == 1
        taxon.x_iucn = iucn[0].descripcion
        validacion_interna_hash['SCAT_IUCN'] = taxon.x_iucn
      else
        validacion_interna_hash['SCAT_IUCN'] = nil
      end

      #cites = taxon.estados_conservacion.where('nivel1=4 AND nivel2=3 AND nivel3>0').distinct
      cites = taxon.catalogos.iucn
      if cites.length == 1
        taxon.x_cites = cites[0].descripcion
        validacion_interna_hash['SCAT_CITES'] = taxon.x_cites
      else
        validacion_interna_hash['SCAT_CITES'] = nil
      end

      # Para el tipo de distribucion
      #tipos_distribuciones = taxon.tipos_distribuciones.map(&:descripcion).uniq
      tipos_distribuciones = taxon.tipos_distribuciones.map(&:descripcion).uniq

      if tipos_distribuciones.any?
        taxon.x_tipo_distribucion = tipos_distribuciones.join(',')
        validacion_interna_hash['SCAT_Distribucion'] = taxon.x_tipo_distribucion
      else
        validacion_interna_hash['SCAT_Distribucion'] = nil
      end

      validacion_interna_hash['SCAT_CatalogoDiccionario'] = taxon.sist_clas_cat_dicc
      validacion_interna_hash['SCAT_Fuente'] = taxon.fuente
      validacion_interna_hash['ENCICLOVIDA'] = "http://www.enciclovida.mx/especies/#{taxon.id}"

    else  # Asociacion vacia, solo el error
      columnas.each do |columna|
        validacion_interna_hash[columna] = nil  # Por default la pongo vacia

        case columna
          when 'SCAT_Familia_valido'
            validacion_interna_hash[columna] = [fila['familia'], INFORMACION_ORIG] if fila['familia'].present?
          when 'SCAT_Genero_valido'
            validacion_interna_hash[columna] = [fila['genero'], INFORMACION_ORIG] if fila['genero'].present?
          when 'SCAT_Especie_valido'
            validacion_interna_hash[columna] = [fila['especie'], INFORMACION_ORIG] if fila['especie'].present?
          when 'SCAT_AutorEspecie_valido'
            validacion_interna_hash[columna] = [fila['nombre_autoridad'], INFORMACION_ORIG] if fila['nombre_autoridad'].present?
          when 'SCAT_Infraespecie_valido'
            validacion_interna_hash[columna] = [fila['infraespecie'], INFORMACION_ORIG] if fila['infraespecie'].present?
          when 'SCAT_Categoria_valido'
            validacion_interna_hash[columna] = [fila['categoria_taxonomica'], INFORMACION_ORIG] if fila['categoria_taxonomica'].present?
          when 'SCAT_NombreCient_valido'
            validacion_interna_hash[columna] = [fila['nombre_cientifico'], INFORMACION_ORIG] if fila['nombre_cientifico'].present?
        end

      end
    end

    validacion_interna_hash
  end
end