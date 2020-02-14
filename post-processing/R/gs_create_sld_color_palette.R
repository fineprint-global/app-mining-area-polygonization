gs_create_sld_color_palette <- function(x){
  
  sld <- xml2::read_xml('<?xml version="1.0" encoding="UTF-8"?>
    <sld:StyledLayerDescriptor xmlns="http://www.opengis.net/sld" xmlns:gml="http://www.opengis.net/gml" xmlns:ogc="http://www.opengis.net/ogc" xmlns:sld="http://www.opengis.net/sld" version="1.0.0">
    <sld:UserLayer>
    <sld:LayerFeatureConstraints>
      <sld:FeatureTypeConstraint/>
    </sld:LayerFeatureConstraints>
    <sld:UserStyle>
      <sld:Title/>
      <sld:FeatureTypeStyle>
        <sld:Rule>
          <sld:RasterSymbolizer>
            <sld:Geometry>
              <ogc:PropertyName>grid</ogc:PropertyName>
            </sld:Geometry>
            <sld:Opacity>1</sld:Opacity>
            <sld:ColorMap type="intervals" extended="true">
            </sld:ColorMap>
          </sld:RasterSymbolizer>
        </sld:Rule>
      </sld:FeatureTypeStyle>
    </sld:UserStyle>
    </sld:UserLayer>
  </sld:StyledLayerDescriptor>')
  
  x[nrow(x),2] <- as.numeric(x[nrow(x),2]) + 1
  
  for(j in 1:nrow(x)){
    sld %>% 
      xml2::xml_child(., "sld:UserLayer") %>%
      xml2::xml_child(., "sld:UserStyle") %>%
      xml2::xml_child(., "sld:FeatureTypeStyle") %>%
      xml2::xml_child(., "sld:Rule") %>%
      xml2::xml_child(., "sld:RasterSymbolizer") %>%
      xml2::xml_child(., "sld:ColorMap") %>%
      xml2::xml_add_child(., "sld:ColorMapEntry", color=stringr::str_sub(x[j,3], start = 1, end = 7), label=x[j,4], opacity="1", quantity=x[j,2], .where = "after") %>% 
      xml_root()
  }
  
  # message(sld)
  return(sld)
  
}
