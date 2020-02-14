gs_create_jenks_breaks_color_palette <- function(src, k, option = "inferno", begin = 0.2, end = 1.0, direction = -1){
  
  z_value <- raster::raster(src) %>% 
    raster::values() 
  
  z_value <- z_value[!is.na(z_value)] 
  
  z_class <- BAMMtools::getJenksBreaks(z_value, k = k) 
  
  m_class <- matrix(c(0, z_class[-length(z_class)], z_class), ncol = 2)
  
  m_class <- cbind(m_class, viridis::viridis(option = "inferno", begin = begin, end = end, direction = direction, n = k)) %>% 
    cbind(paste(paste0("(", m_class[,1]), paste0(m_class[,2], "]"), sep = ","))
  
  return(m_class)
  
}
