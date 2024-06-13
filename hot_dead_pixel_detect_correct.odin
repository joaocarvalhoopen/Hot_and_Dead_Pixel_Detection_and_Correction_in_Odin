// Project name : Hot and Dead Pixel Detection and Correction in Odin
//                A simple yet interesting program that shows the performance of the Odin language.
//
// Date         : 2024.06.13
//
// Author       : João Carvalho
//
// Description  : This program is to be used as part of a final program, and
//                it's a prototype program to play with the ideas and algorithms.
//                It loads a image jpeg, png, spreads N hot and dead pixels in the
//                image, then it detects the positions of the hot pixels and the
//                dead pixels (the heaviest part of the algorithm) and then it
//                corrects the hot and dead pixels and saves the final image.
//                If you read and write jpg's file format for a 10 mega pixel
//                image of 3600 x 2700 image, and only save once the final image,
//                this algorithm only takes 0.4 seconds to run. In the future, it
//                can be greatly optimized with SIMD instructions and other
//                optimizations. The algorithm is based on the idea of kernels
//                for the detection of hot and dead pixels. In the practical case,
//                one would use the hot and dead pixel detection to create a map
//                of the hot and dead pixels on several images and then use the
//                map that is common to more of the images for that camera, to
//                correct the hot and dead pixels. Used in that way the algorithm
//                is very fast and low overhead. In principle this algorithm could
//                be used for image processing and for the processing of each frame
//                before compression into a video.
//
// Libs used    : This program uses the stb_image library to load and save images,
//                that comes with the Odin vendors API.
//                Don't forget that to compile this program, you need to have previoslly
//                compiled the stb lib.
//
//                # In Linux do :
//
//                $ cd Odin/vendors/stb/src
//                $ make
//                
//                # Then go to where you have this project and do :
// 
//                $ make
//
//                # or 
//
//                $ make opti
//
//                $ make run
//
// License      : MIT Open Source License
//

package hot_dead_pixel_detect_correct

import "core:fmt"
import "core:strings"
import "core:math"
import "core:os"
import "core:slice"

import img "vendor:stb/image"

import "core:math/rand"

NUM_CHANNELS : i32 = 3

Img_Type :: enum {
    None,
    PNG,
    JPG,
    BMP,
    TGA,
    GIF,
    PSD,
    HDR,
    PIC,
    PNM,
}

// Internal color
RGBA :: struct #packed {
    r    : u8,
    g    : u8,
    b    : u8,
    a    : u8,
}

// Represents one plot.
Image :: struct {
    path_name_source  : string,
    path_name_target  : string,
    file_type         : Img_Type,    
    size_x            : i32,
    size_y            : i32,
    // Number of components per pixel.
    components        : i32,              // 3 RGB, 4 RGBA
    // This is the RGBA image data buffer.
    img_buffer        : []u8,
}

HOT_PIXEL  : RGBA = RGBA { r = 255, g = 255, b = 255, a = 255 }

DEAD_PIXEL : RGBA = RGBA { r = 0, g = 0, b = 0, a = 255 }

Coord :: struct {
    x : i32,
    y : i32,
}

Pixels_With_Problems :: struct {
    hot_pixels_list  : [dynamic]Coord,
    dead_pixels_list : [dynamic]Coord,
}

get_image_type :: proc ( path_name : string ) -> Img_Type {
    // Get the file extension.
    lower := strings.to_lower( path_name )

    // Check the extension.
    switch {
        case strings.has_suffix( lower, ".png" ):
            return Img_Type.PNG
        case strings.has_suffix( lower, ".jpg" ):
            return Img_Type.JPG
        case strings.has_suffix( lower, ".jpeg" ):
            return Img_Type.JPG
        case strings.has_suffix( lower, ".bmp" ):
            return Img_Type.BMP
        case strings.has_suffix( lower, ".tga" ):
            return Img_Type.TGA
        case strings.has_suffix( lower, ".gif" ):
            return Img_Type.GIF
        case strings.has_suffix( lower, ".psd" ):
            return Img_Type.PSD
        case strings.has_suffix( lower, ".hdr" ):
            return Img_Type.HDR
        case strings.has_suffix( lower, ".pic" ):
            return Img_Type.PIC
        case strings.has_suffix( lower, ".pnm" ):
            return Img_Type.PNM
    }

    return Img_Type.None
}

// Create a copy of the path_name string with the "_copy_" sufix
// added before last dot, exemple .jpeg extension.
image_path_name_inject :: proc ( path_name : string, injected_str : string ) -> string {
 
    // Find the last dot.
    dot_pos := strings.last_index( path_name, "." )

    // Check if the dot was found.
    if dot_pos == -1 {
        return fmt.aprintf( "%s%s", path_name, injected_str )
    } else {
        return fmt.aprintf( "%s%s%s",
                            path_name[ : dot_pos ],
                            injected_str,
                            path_name[ dot_pos : ]  )
    }
}

image_load :: proc ( path_name_source : string, path_name_target : string ) ->
                   ( res_image : Image, ok : bool ) {
    size_x     : i32 = 0
    size_y     : i32 = 0
    components : i32 = 0
    
    // Load the image from the file.
    data : [ ^ ]u8 = img.load( strings.clone_to_cstring( path_name_source ), 
                                 & size_x,
                                 & size_y,
                                 & components,
                                 3 )

    // Check if the image was loaded.
    if data == nil {
        fmt.printfln( "Error loading image: %s", path_name_source )
        ok := false
        res_image := Image{}
        return res_image, ok
    }

    // Create the image object.
    res_image = Image {
        path_name_source = strings.clone( path_name_source ),
        path_name_target = image_path_name_inject( path_name_target, "__copy" ),
        file_type      = get_image_type( path_name_source ),
        size_x         = size_x,
        size_y         = size_y,
        components     = components,
        // img_buffer     = ( transmute( [ ^ ]Pixel ) data )[ 0 : size_x * size_y ],
        img_buffer     = data[ 0 : size_x * size_y * NUM_CHANNELS ],
    }

    return res_image, true
}

image_save :: proc ( image: ^Image, with_name : ^string = nil ) {

    file_name : string
    if with_name == nil {
        file_name = image^.path_name_target 
    } else {
        file_name = image_path_name_inject( image^.path_name_target,
                                            with_name^ )
    }
    
    // stride is in bytes.
    stride : i32 = image.size_x * NUM_CHANNELS

    ret : i32

    switch image^.file_type {
        case Img_Type.PNG:
            ret = img.write_png( 
                        strings.clone_to_cstring( file_name ),
                        image.size_x,
                        image.size_y,
                        image.components,                        // 4 components: RGBA
                        rawptr( & ( image^.img_buffer[ 0 ] ) ),  // &data[0],
                        stride )  // in bytes

        case Img_Type.JPG:
            ret = img.write_jpg( 
                        strings.clone_to_cstring( file_name ),
                        image.size_x,
                        image.size_y,
                        image.components,                        // 4 components: RGBA
                        rawptr( & ( image^.img_buffer[ 0 ] ) ),  // &data[0],
                        0 )   // No compression

                        // stride )

        case Img_Type.BMP:
            ret = img.write_bmp( 
                        strings.clone_to_cstring( file_name ),
                        image.size_x,
                        image.size_y,
                        image.components,                        // 4 components: RGBA
                        rawptr( & ( image^.img_buffer[ 0 ] ) ),  // &data[0],
                        // stride
                        )

        case Img_Type.TGA:
            ret = img.write_tga( 
                        strings.clone_to_cstring( file_name ),
                        image.size_x,
                        image.size_y,
                        image.components,                   // 4 components: RGBA
                        rawptr( & ( image^.img_buffer[ 0 ] ) ),  // &data[0],
                        // stride
                        )

        case Img_Type.GIF:
            fmt.printfln( "Error: Writing GIF format, Unsupported image type: %d",
                          image.file_type )
            os.exit( 1 )

        case Img_Type.PSD:
            fmt.printfln( "Error: Writing PSD format, Unsupported image type: %d",
                          image.file_type )
            os.exit( 1 )

        case Img_Type.HDR:
            img.write_tga( 
                strings.clone_to_cstring( file_name ),
                image.size_x,
                image.size_y,
                image.components,                        // 4 components: RGBA
                rawptr( & ( image^.img_buffer[ 0 ] ) ),  // &data[0],
                // stride
                )

        case Img_Type.PIC:
            fmt.printfln( "Error: Writing PIC format, Unsupported image type: %d",
                          image.file_type )
            os.exit( 1 )

        case Img_Type.PNM:
            fmt.printfln( "Error: Writing PIC format, Unsupported image type: %d",
                          image.file_type )
            os.exit( 1 )

        case Img_Type.None:
            fmt.printfln( "Error: Unsupported image type: %v, %v",
                          image.file_type, file_name )
            os.exit( 1 )

        case:
            fmt.printfln( "Error: Unsupported image type: %v, %v",
                          image.file_type, file_name )
            os.exit( 1 )
    }

    if ret != 1 {
        fmt.printfln( "Error saving image: %s, ret: %v", file_name, ret )
    }

}

image_free :: proc ( image : ^Image ) {
    delete( image^.path_name_source )
    delete( image^.path_name_target )
    
    // Free the data.
    img.image_free( & image^.img_buffer[ 0 ] )
    
    //delete( image^.img_buffer )
    image^.img_buffer = nil
}

image_info_print :: proc ( image : ^Image ) {

    fmt.printfln( "Image: \n" + 
                        "  path_name_orig: %s,\n" +
                        "  path_name_des:  %s,\n" +
                        "              x:  %d,\n" +
                        "              y:  %d,\n" +
                        "     components:  %d\n\n",
                  image.path_name_source,
                  image.path_name_target,
                  image.size_x,
                  image.size_y,
                  image.components )
}   

image_get_pixel :: #force_inline proc ( image : ^Image, x : i32, y : i32 ) -> 
                                      ( r: u8, g: u8, b: u8 ) {
    // img_buffer := image^.img_buffer
    index := 3 * ( y * image.size_x + x ) 
    r = image^.img_buffer[ index ]
    g = image^.img_buffer[ index + 1 ]
    b = image^.img_buffer[ index + 2 ]    
    return r, g, b
    // return image^.img_buffer[ x * image.size_y + y ]
}

image_set_pixel :: #force_inline proc ( image : ^Image, x : i32, y : i32, r : u8, g: u8, b: u8 ) {
    // fmt.printfln( "set_pixel -> x : %d, y : %d", x, y )

    // img_buffer := image^.img_buffer
    index := 3 * ( y * image.size_x + x )
    image^.img_buffer[ index ]     = r
    image^.img_buffer[ index + 1 ] = g
    image^.img_buffer[ index + 2 ] = b
}

add_random_hot_and_dead_pixels :: proc ( image : ^Image, hot_num : int, dead_num : int ) ->
                                         Pixels_With_Problems {
    // Add random hot and dead pixels to the image.
    // For now, just copy the image.


    seed : u64 = 42
    rand_gen := rand.create( seed )

    hot_pixels_list := make( [ dynamic ]Coord, len = 0, cap = hot_num )
    if hot_pixels_list == nil {
        fmt.printfln( "Error creating hot pixels list..." )
        os.exit( 1 )
    }

    dead_pixels_list := make( [ dynamic ]Coord, len = 0, cap = dead_num )
    if dead_pixels_list == nil {
        fmt.printfln( "Error creating dead pixels list..." )
        os.exit( 1 )
    }

    // Add random HOT pixels.
    for i in 0 ..< hot_num {
        x := rand.int31_max( image.size_x, & rand_gen )
        y := rand.int31_max( image.size_y, & rand_gen )
        append_elem( & hot_pixels_list, Coord { x = x, y = y } )
        image_set_pixel( image, x, y,
                         HOT_PIXEL.r, HOT_PIXEL.g, HOT_PIXEL.b )
    }

    // Add random DEAD pixels.
    for i in 0 ..< dead_num {
        x := rand.int31_max( image.size_x, & rand_gen )
        y := rand.int31_max( image.size_y, & rand_gen )
        append_elem( & dead_pixels_list, Coord { x = x, y = y } )
        image_set_pixel( image, x, y,
                         DEAD_PIXEL.r, DEAD_PIXEL.g, DEAD_PIXEL.b )
    }

    // Create the object with the pixels with problems.
    pixels_with_problems := Pixels_With_Problems {
        hot_pixels_list  = hot_pixels_list,
        dead_pixels_list = dead_pixels_list,
    }

    return pixels_with_problems
}

// Kernel for the center, majotity of the pixels.
kernel := [?]Coord { Coord{ -1 , -1 }, Coord{ 0 , -1 }, Coord{ 1 , -1 },
                     Coord{ -1 ,  0 },                  Coord{ 1 ,  0 },
                     Coord{ -1 ,  1 }, Coord{ 0 ,  1 }, Coord{ 1 , -1 } }

// Kerneis for the borders.

kernel_up := [?]Coord { /* Coord{ -1 , -1 }, Coord{ 0 , -1 }, Coord{ 1 , -1 }, */
                        Coord{ -1 ,  0 },                  Coord{ 1 ,  0 },
                        Coord{ -1 ,  1 }, Coord{ 0 ,  1 }, Coord{ 1 , -1 } }

kernel_down := [?]Coord { Coord{ -1 , -1 }, Coord{ 0 , -1 }, Coord{ 1 , -1 },
                        Coord{ -1 ,  0 },                  Coord{ 1 ,  0 } /*,
                        Coord{ -1 ,  1 }, Coord{ 0 ,  1 }, Coord{ 1 , -1 } */ }

kernel_left := [?]Coord { /* Coord{ -1 , -1 }, */  Coord{ 0 , -1 }, Coord{ 1 , -1 },
                          /* Coord{ -1 ,  0 }, */                  Coord{ 1 ,  0 },
                          /* Coord{ -1 ,  1 }, */ Coord{ 0 ,  1 }, Coord{ 1 , -1 } }

kernel_right := [?]Coord { Coord{ -1 , -1 }, Coord{ 0 , -1 }, /* Coord{ 1 , -1 }, */
                     Coord{ -1 ,  0 },                  /* Coord{ 1 ,  0 }, */
                     Coord{ -1 ,  1 }, Coord{ 0 ,  1 }  /*, Coord{ 1 , -1 } */ }
     

apply_kernel :: #force_inline proc ( image : ^Image, x : i32, y : i32, kernel : []Coord ) ->
                                   ( m_r,     m_g,   m_b : u8,
                                     min_r, min_g, min_b : u8,
                                     max_r, max_g, max_b : u8 ) {
    // Apply the kernel to the image.

    min_r = 255
    min_g = 255
    min_b = 255

    max_r = 0
    max_g = 0
    max_b = 0

    r := 0
    g := 0
    b := 0
    count := 0

    for i in 0 ..< len( kernel ) {
        x1 := x + kernel[ i ].x
        y1 := y + kernel[ i ].y

        // if x1 < 0 || x1 >= image.size_x || y1 < 0 || y1 >= image.size_y {
        //     continue
        // }

        r1, g1, b1 := image_get_pixel( image, x1, y1 )
        r += int( r1 )
        g += int( g1 )
        b += int( b1 )

        if r1 < min_r do min_r = r1
        if g1 < min_g do min_g = g1
        if b1 < min_b do min_b = b1

        if r1 > max_r do max_r = r1
        if g1 > max_g do max_g = g1
        if b1 > max_b do max_b = b1
        
        count += 1
    }

    m_r = u8( r / count )
    m_g = u8( g / count )
    m_b = u8( b / count )

    return m_r,     m_g,   m_b,
           min_r, min_g, min_b,
           max_r, max_g, max_b
}

image_detect_hot_dead_pixels :: proc ( image : ^Image ) -> Pixels_With_Problems {
    // Detect hot and dead pixels in the image.
    
    hot_pixels_list  := make( [dynamic]Coord, len=0, cap = 1000 )
    if hot_pixels_list == nil {
        fmt.printfln( "Error creating hot pixels list..." )
        os.exit( 1 )
    }
    dead_pixels_list := make( [dynamic]Coord, len=0, cap = 1000 )
    if dead_pixels_list == nil {
        fmt.printfln( "Error creating dead pixels list..." )
        os.exit( 1 )
    }

    Pixels_With_Problems_detected := Pixels_With_Problems{ 
        hot_pixels_list  = hot_pixels_list,
        dead_pixels_list = dead_pixels_list,
    }

    for y in 0 ..< image.size_y {
        for x in 0 ..< image.size_x {
            if x == 0 || y == 0 || x == image.size_x - 1 || y == image.size_y - 1 {
                
                // TODO
                // We are at the borders, the uppest and lowest line and
                // the left most and right most line, the processing in here will be ignored for know.
                // but it's all in place to process also this case.
                // The processing has to take into account a different kernel for each line side
                // all around the image, so that it doesn't access the pixeis that don't exist.
                continue
            }

            m_r,     m_g,   m_b,
            min_r, min_g, min_b,
            max_r, max_g, max_b := apply_kernel( image, x, y, kernel[ : ] )

            r, g, b := image_get_pixel( image, x, y )
           
            delta : int = int( r ) - int( m_r ) + int( g ) - int( m_g ) + int( b ) - int( m_b )

            // Check if the pixel is a invalid lower. [ 0, 0 , 0 ]
            // All the components around must be greater or equal to the center pixel,
            // so, in order for a pixel to be valid it's max must be negative or zero.
            greater_or_equal := math.max( int( r ) - int( min_r ),
                                          int( g ) - int( min_g ),
                                          int( b ) - int( min_b ) )
            
            // If it is greater than zero, the pixel is invalid,
            // because that means that at least one component is lower then the center pixel.
            flag_center_invalid_lower := true if greater_or_equal > 0 else false

            // Check if the pixel is a invalid upper. [ 255. 255, 255 ]
            // All the components around must be lower or equal to the center pixel,
            // so, in order for a pixel to be valid it's max must be positive or zero.
            lower_or_equal := math.min( int( r ) - int( max_r ),
                                        int( g ) - int( max_g ),
                                        int( b ) - int( max_b ) )
            
            // If it is lower than zero, the pixel is invalid,
            // because that means that at least one component is lower then the center pixel.
            flag_center_invalid_upper := true if lower_or_equal < 0 else false

            pixel_point_componentes_lower_10 := true if ( r < 10 && g < 10 && b < 10 ) else false

            pixel_point_componentes_upper_245 := true if ( r > 245 && g > 245 && b > 245 ) else false

            if pixel_point_componentes_lower_10 &&
               !flag_center_invalid_lower &&
               // ( delta < int( math.round_f32( -255.0 / 1.75 ) ) ) {
               ( delta < int( math.round_f32( -255.0 / 4.75 ) ) ) {
                
                // fmt.printfln( "Dead pixel detected at: x: %d, y: %d", x, y )
                append_elem( & Pixels_With_Problems_detected.dead_pixels_list, Coord { x = x, y = y } )

            } else if pixel_point_componentes_upper_245 &&
                      !flag_center_invalid_upper &&
                      ( delta > int( math.round_f32( 255.0 / 1.75 ) ) ) {
                
                // fmt.printfln( "Hot pixel detected at: x: %d, y: %d", x, y )
                append_elem( & Pixels_With_Problems_detected.hot_pixels_list, Coord { x = x, y = y } )
            
            } 
    
            // // if delta < int( math.round_f32( -255.0 / 1.65 ) ) {
            // // if delta < int( math.round_f32( -255.0 / 1.2 ) ) {
            // if delta < int( math.round_f32( -255.0 / 1.75 ) ) {
            //     // fmt.printfln( "Dead pixel detected at: x: %d, y: %d", x, y )
            //     append_elem( & Pixels_With_Problems_detected.dead_pixels_list, Coord { x = x, y = y } )
            // } else if delta > int( math.round_f32( 255.0 / 1.75 ) ) {
            //     // fmt.printfln( "Hot pixel detected at: x: %d, y: %d", x, y )
            //     append_elem( & Pixels_With_Problems_detected.hot_pixels_list, Coord { x = x, y = y } )
            // } 

        }
    }    
    
    return Pixels_With_Problems_detected
}

compare_pixeis_with_problems :: proc ( pixels_with_problems          : Pixels_With_Problems, 
                                       pixels_with_problems_detected : Pixels_With_Problems ) ->
                                     ( pixels_with_problems_not_found : Pixels_With_Problems ) {
    // Compare the pixels_with_problems with pixels_with_problem_detected.

    fmt.printfln( "\nComparing pixels with problems...\n" )


    hot_pixel_not_found  := slice.clone_to_dynamic( pixels_with_problems_detected.hot_pixels_list[ : ] )
    dead_pixel_not_found := slice.clone_to_dynamic( pixels_with_problems_detected.dead_pixels_list[ : ] )

    // HOT Pixeis detection and filtering.
    counter_hot := 0
    for i in 0 ..< len( pixels_with_problems.hot_pixels_list ) {
        point := pixels_with_problems.hot_pixels_list[ i ]

        // Compare the hot pixels.
        flag_found : bool = false
        for j in 0 ..< len( pixels_with_problems_detected.hot_pixels_list ) {
            if point == pixels_with_problems_detected.hot_pixels_list[ j ] {
                flag_found = true
                break
            }
        }
        if !flag_found {
            // fmt.printfln( "Hot pixel not detected at: x: %d, y: %d", 
            //               pixels_with_problems.hot_pixels_list[ i ].x,
            //               pixels_with_problems.hot_pixels_list[ i ].y )
            counter_hot += 1
        }
        
        // Remove the hot pixel from the list of not found.
        for j in 0 ..< len( hot_pixel_not_found ) {
            if point == hot_pixel_not_found[ j ] {
                unordered_remove( & hot_pixel_not_found, j )
                break
            }
        }
    }
    counter_hot_wrong := len( hot_pixel_not_found )

    // DEAD Pixeis detection and filtering.
    counter_dead := 0
    for i in 0 ..< len( pixels_with_problems.dead_pixels_list ) {
        point := pixels_with_problems.dead_pixels_list[ i ]

        // Compare the dead pixels.
        flag_found : bool = false
        for j in 0 ..< len( pixels_with_problems_detected.dead_pixels_list ) {
            if point == pixels_with_problems_detected.dead_pixels_list[ j ] {
                flag_found = true
                break
            }
        }
        if !flag_found {
            // fmt.printfln( "Hot pixel not detected at: x: %d, y: %d", 
            //               pixels_with_problems.dead_pixels_list[ i ].x,
            //               pixels_with_problems.dead_pixels_list[ i ].y )
            counter_dead += 1
        }

        // Remove the dead pixel from the list of not found.
        for j in 0 ..< len( dead_pixel_not_found ) {
            if point == dead_pixel_not_found[ j ] {
                unordered_remove( & dead_pixel_not_found, j )
                break
            }
        }
    }
    counter_dead_wrong := len( dead_pixel_not_found )

    fmt.printfln( "Hot pixels not detected correct: %d / %d <- create " + 
                  " [detected all %d], [detected wrong: %d ]\n",
                  counter_hot,
                  len( pixels_with_problems.hot_pixels_list ),
                  len( pixels_with_problems_detected.hot_pixels_list ),
                  counter_hot_wrong )

    fmt.printfln( "Dead pixels not detected correct: %d / %d <- create " + 
                  " [detected all %d]. [detected wrong: %d]\n",
                  counter_dead,
                  len( pixels_with_problems.dead_pixels_list ),
                  len( pixels_with_problems_detected.dead_pixels_list ),
                  counter_dead_wrong)

    return Pixels_With_Problems { hot_pixels_list = hot_pixel_not_found,
                                  dead_pixels_list = dead_pixel_not_found }
}

pixeis_print :: proc ( image : ^Image, pixels_with_problems_not_found : Pixels_With_Problems ) {
    fmt.printfln( "\nPixeis not found...\n" )

    fmt.printfln( "Hot pixels not found: %d\n",
        len( pixels_with_problems_not_found.hot_pixels_list ) )
    for i in 0 ..< len( pixels_with_problems_not_found.hot_pixels_list ) {
        p := pixels_with_problems_not_found.hot_pixels_list[ i ]
        fmt.printfln( "    x: %d, y: %d,  rgb [%v, %v, %v]",
                      p.x,
                      p.y,
                      image_get_pixel( image, p.x, p.y ) )
        
    }

    fmt.printfln( "\nDead pixels not found: %d\n",
        len( pixels_with_problems_not_found.dead_pixels_list ) )
    for i in 0 ..< len( pixels_with_problems_not_found.dead_pixels_list ) {
        p := pixels_with_problems_not_found.dead_pixels_list[ i ]
        fmt.printfln( "    x: %d, y: %d, rgb [%v, %v, %v]",
                      p.x,
                      p.y,
                      image_get_pixel( image, p.x, p.y ) )
    }
}

image_correct_hot_dead_pixels :: proc ( image : ^Image, pixels_with_problems_detected : Pixels_With_Problems ) {
    // Correct hot and dead pixels in the image.

    // Corrrect the hot pixels.
    for i in 0 ..< len( pixels_with_problems_detected.hot_pixels_list ) {
        x := pixels_with_problems_detected.hot_pixels_list[ i ].x
        y := pixels_with_problems_detected.hot_pixels_list[ i ].y
        
        m_r, m_g, m_b,
        _, _ , _ ,
        _, _ , _   := apply_kernel( image, x, y, kernel[ : ] )
        
        image_set_pixel( image, x, y, m_r, m_g, m_b )
    }

    // Corrrect the dead pixels.
    for i in 0 ..< len( pixels_with_problems_detected.dead_pixels_list ) {
        x := pixels_with_problems_detected.dead_pixels_list[ i ].x
        y := pixels_with_problems_detected.dead_pixels_list[ i ].y
        
        m_r, m_g, m_b,
        _, _ , _ ,
        _, _ , _  := apply_kernel( image, x, y, kernel[ : ] )
        
        image_set_pixel( image, x, y, m_r, m_g, m_b )
    }

}

image_process :: proc ( image : ^Image, pixels_with_problems : Pixels_With_Problems ) {
    // Process the image.
    // For now, just copy the image.
     
    pixels_with_problems_detected := image_detect_hot_dead_pixels( image )

    fmt.printfln( "\nPixels with problems detected...\n" +
                        "         hot_pixels_list:   %d\n" +
                        "         dead_pixels_list:  %d\n ",
                        len( pixels_with_problems_detected.hot_pixels_list ),
                        len( pixels_with_problems_detected.dead_pixels_list )
                     )

    pixels_with_problems_not_found := compare_pixeis_with_problems(
                                    pixels_with_problems,
                                    pixels_with_problems_detected )

    pixeis_print( image, pixels_with_problems_not_found )

    image_correct_hot_dead_pixels( image, pixels_with_problems_detected )

    // Compare the pixels_with_problems with pixels_with_problem_detected.
    // TODO: 
}

main :: proc ( ) {
    fmt.printfln( "Begin Hot/Dead pixel detect and correct...\n" )

    image_source_path := "./images_source/clock_01.jpg"
    image_target_path := "./images_target/clock_01_proc.png"

    // Load the image.
    image, ok := image_load( image_source_path, image_target_path )
    if !ok {
        fmt.printfln( "Error loading image..." )
        return
    }
    fmt.printfln( "Image loaded: %s, %d x %d, components: %d",
                  image.path_name_source, image.size_x, image.size_y, image.components )


    image.file_type = Img_Type.PNG

    image_info_print( & image )

    hot_num  := 25000 // 250   // 50
    dead_num := 25000 // 250   // 50

    // Add random hot and dead pixels.
    pixels_with_problems := add_random_hot_and_dead_pixels( 
            & image, hot_num, dead_num )

    with_name  := "_hot_dead"    
    image_save( & image, & with_name )


    // Process the image.
    image_process( & image, pixels_with_problems )

    image.file_type = Img_Type.JPG

    // Save the image.
    with_name = "_final"
    image_save( & image, & with_name )
    fmt.printfln( "Image saved: %s", image.path_name_target )

    // Free the image.
    image_free( & image )

    fmt.printfln( "\nEnd of Hot/Dead pixel detect and correct...\n" )
}


// TODO:

// Fazer uma estatisticas de todos os hot e dead pixies aleatorios adicionados
// para determinar melhores critério
// para todos os pixeis nomeadamente aqueles escuros em relação aos pontos pretos.
// Ver se o ponto está muito proximo de preto ou de branco e se todos os outros pixeis à
// volta estão a ir no sentido contrario,
// ou seja ver se aquele pixel é muito ou pouco divergente.

// Mas tenho de fazer a estatistica dos pontos que não estão a ser encontrados e ver se
// consigo pensar em criterios de selecção.

