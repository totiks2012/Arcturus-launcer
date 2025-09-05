#p1

#!/usr/bin/env wish
package require Tk

wm withdraw .
set BASE_DIR [pwd]
set BUTTON_DIR [file join $BASE_DIR ".launcher_buttons"]
set ICON_CACHE_DIR [file join $BASE_DIR ".launcher_icon_cache"]
set CONFIG_FILE [file join $BASE_DIR "config.conf"]
set ICON_TYPE_CACHE_FILE [file join $ICON_CACHE_DIR ".icon_type_cache"]
set PINNED_FILE [file join $BASE_DIR ".launcher_pinned"]
set button_to_desktop [dict create]
set search_terms [dict create]
set ICON_TYPE_CACHE [dict create]
set cache_desktop_files [dict create]
set cache_app_info [dict create]
set cached_icons [dict create]
set cached_terminal_cmd ""
set results_visible 0
set search_timer ""
set pinned_icons [dict create]
set config [dict create Layout [dict create button_padding 10 icon_scale 1.0 bg_left "#d9d9d9" bg_right "#ffffff" font_color "#000000" cat_font_color "#000000" selection_color "#87CEEB" button_border_color "#808080" search_entry_border_width 0]]
set categories {"Все" {Network WebBrowser Email Chat Office WordProcessor Spreadsheet Presentation Utility FileTools Calculator System Settings Administration Audio Video}}
set cache_built 0

#p2

# Загрузка и сохранение кэша иконок
proc load_icon_type_cache {} {
    global ICON_TYPE_CACHE ICON_TYPE_CACHE_FILE
    if {[file exists $ICON_TYPE_CACHE_FILE]} {
        set fd [open $ICON_TYPE_CACHE_FILE r]
        set data [read $fd]
        close $fd
        set ICON_TYPE_CACHE [dict create {*}$data]
    }
}

proc save_icon_type_cache {} {
    global ICON_TYPE_CACHE ICON_TYPE_CACHE_FILE
    set fd [open $ICON_TYPE_CACHE_FILE w]
    puts $fd $ICON_TYPE_CACHE
    close $fd
}

# Загрузка и сохранение конфигурации
proc load_config {} {
    global CONFIG_FILE config
    if {[file exists $CONFIG_FILE]} {
        set fd [open $CONFIG_FILE r]
        set data [read $fd]
        close $fd
        foreach line [split $data "\n"] {
            set line [string trim $line]
            if {[string match "\[Layout\]" $line]} {continue}
            foreach key {button_padding icon_scale bg_left bg_right font_color cat_font_color selection_color button_border_color search_entry_border_width font_family font_size} {
                if {[string match "${key}=*" $line]} {
                    set value [string trim [string range $line [expr {[string first "=" $line] + 1}] end]]
                    if {$key eq "icon_scale" && [regexp {^[0-9]+\.?[0-9]*$} $value] && $value >= 0.5 && $value <= 3.0} {
                        dict set config Layout $key $value
                    } elseif {$key eq "font_size" && [regexp {^[0-9]+$} $value] && $value >= 8 && $value <= 20} {
                        dict set config Layout $key $value
                    } elseif {$key eq "font_family"} {
                        dict set config Layout $key $value
                    } elseif {[string match "bg_*" $key] || [string match "*color" $key] && [regexp {^#[0-9a-fA-F]{6}$} $value]} {
                        dict set config Layout $key $value
                    } elseif {$key eq "button_padding" && [regexp {^[0-9]+$} $value]} {
                        dict set config Layout $key $value
                    } elseif {$key eq "search_entry_border_width" && [regexp {^[0-5]$} $value]} {
                        dict set config Layout $key $value
                    }
                }
            }
        }
    }
    
    # Установка значений по умолчанию, если они отсутствуют
    if {![dict exists $config Layout font_family]} {
        dict set config Layout font_family "TkDefaultFont"
    }
    if {![dict exists $config Layout font_size]} {
        dict set config Layout font_size 9
    }
}

proc save_config {} {
    global CONFIG_FILE config
    set fd [open $CONFIG_FILE w]
    puts $fd "\[Layout\]"
    foreach key {button_padding icon_scale bg_left bg_right font_color cat_font_color selection_color button_border_color search_entry_border_width font_family font_size} {
        if {[dict exists $config Layout $key]} {
            puts $fd "${key}=[dict get $config Layout $key]"
        }
    }
    close $fd
}

#p3


# Обновление масштаба и создание иконки-заполнителя
proc update_scale {delta} {
    global config main
    set current_scale [dict get $config Layout icon_scale]
    set new_scale [expr {$current_scale + ($delta > 0 ? 0.1 : -0.1)}]
    if {$new_scale >= 0.5 && $new_scale <= 3.0} {
        dict set config Layout icon_scale $new_scale
        apply_scale
        save_config
    }
}

proc apply_scale {} {
    global config main placeholder_icon
    set scale [dict get $config Layout icon_scale]
    set new_size [expr {int(48 * $scale)}]
    if {$new_size < 48} {set new_size 48}
    
    # Удаляем старую иконку, только если она существует
    if {[info exists placeholder_icon] && [image names] ne "" && [lsearch -exact [image names] $placeholder_icon] >= 0} {
        image delete $placeholder_icon
    }
    
    set placeholder_icon [image create photo -width $new_size -height $new_size]
    set default_icon_path "/usr/share/icons/hicolor/48x48/apps/system-run.png"
    if {[file exists $default_icon_path]} {
        catch {
            set temp_img [image create photo -file $default_icon_path]
            $placeholder_icon copy $temp_img -shrink -to 0 0 $new_size $new_size
            image delete $temp_img
        }
    }
}

# Применение цветов
proc apply_colors {} {
    global config main
    $main configure -background [dict get $config Layout bg_right]
    $main.search configure -background [dict get $config Layout bg_right]
    $main.search.entry_frame configure -background [dict get $config Layout selection_color]
    $main.search.entry configure -borderwidth [dict get $config Layout search_entry_border_width]
    
    if {[winfo exists $main.results]} {
        $main.results configure -background [dict get $config Layout bg_right]
        $main.results.canvas configure -background [dict get $config Layout bg_right]
        
        foreach child [$main.results.canvas find withtag window] {
            set widget [$main.results.canvas itemcget $child -window]
            if {[winfo class $widget] eq "Button"} {
                $widget configure -highlightbackground [dict get $config Layout button_border_color]
            }
        }
    }
    
    # Применение цветов к панели закрепленных иконок
    if {[winfo exists $main.pinned]} {
        $main.pinned configure -background [dict get $config Layout bg_right]
        $main.pinned.canvas configure -background [dict get $config Layout bg_right]
        
        foreach child [$main.pinned.canvas find withtag window] {
            set widget [$main.pinned.canvas itemcget $child -window]
            if {[winfo class $widget] eq "Button"} {
                $widget configure -highlightbackground [dict get $config Layout button_border_color]
            }
        }
    }
}

# Применение настроек шрифта
proc apply_font_settings {} {
    global config main
    
    # Проверяем наличие настроек
    if {![dict exists $config Layout font_family] || ![dict exists $config Layout font_size]} {
        return
    }
    
    set font_family [dict get $config Layout font_family]
    set font_size [dict get $config Layout font_size]
    
    # Применяем к элементам интерфейса
    $main.search.entry configure -font "$font_family $font_size"
    $main.search.settings configure -font "$font_family $font_size bold"
    
    # Обновляем надписи в результатах поиска, если они существуют
    if {[winfo exists $main.results]} {
        foreach child [winfo children $main.results.canvas] {
            if {[string match "*.lbl_*" $child]} {
                $child configure -font "$font_family $font_size"
            }
        }
    }
    
    # Обновляем надписи в закрепленных иконках, если они существуют
    if {[winfo exists $main.pinned]} {
        foreach child [winfo children $main.pinned.canvas] {
            if {[string match "*.lbl_*" $child]} {
                $child configure -font "$font_family $font_size"
            }
        }
    }
}

#p4

# Функции для работы с закрепленными иконками
proc load_pinned_icons {} {
    global pinned_icons PINNED_FILE
    
    if {[file exists $PINNED_FILE]} {
        set fd [open $PINNED_FILE r]
        set data [read $fd]
        close $fd
        
        if {$data ne ""} {
            set pinned_icons [dict create {*}$data]
        }
    }
}

proc save_pinned_icons {} {
    global pinned_icons PINNED_FILE
    
    set fd [open $PINNED_FILE w]
    puts $fd $pinned_icons
    close $fd
}

proc is_pinned {name} {
    global pinned_icons
    return [dict exists $pinned_icons $name]
}

proc pin_icon {button name exec_cmd desktop_file} {
    global pinned_icons PINNED_FILE main
    
    # Добавляем иконку в список закрепленных
    dict set pinned_icons $name [list $exec_cmd $desktop_file]
    
    # Сохраняем список закрепленных иконок
    save_pinned_icons
    
    # Обновляем отображение
    if {[winfo exists $main.results]} {
        # Если панель результатов открыта, обновляем её
        set query [$main.search.entry get]
        if {$query eq ""} {
            # Если поиск пустой, показываем только закрепленные
            display_icons "pinned_only"
        } else {
            # Если есть поисковый запрос, обновляем результаты
            fuzzy_search $query "Все"
        }
    }
    
    # Обновляем настройки, если они открыты
    if {[winfo exists .settings]} {
        destroy .settings.frame.pinned
        add_pinned_tab_to_settings
    }
}

proc unpin_icon {name} {
    global pinned_icons PINNED_FILE main
    
    # Удаляем иконку из списка закрепленных
    dict unset pinned_icons $name
    
    # Сохраняем список закрепленных иконок
    save_pinned_icons
    
    # Обновляем отображение
    if {[winfo exists $main.results]} {
        # Если панель результатов открыта, обновляем её
        set query [$main.search.entry get]
        if {$query eq ""} {
            # Если поиск пустой, показываем только закрепленные
            display_icons "pinned_only"
        } else {
            # Если есть поисковый запрос, обновляем результаты
            fuzzy_search $query "Все"
        }
    }
    
    # Обновляем настройки, если они открыты
    if {[winfo exists .settings]} {
        destroy .settings.frame.pinned
        add_pinned_tab_to_settings
    }
}

# Перемещение закрепленной иконки влево
proc move_icon_left {name} {
    global pinned_icons
    
    # Получаем список имен
    set names [dict keys $pinned_icons]
    set pos [lsearch -exact $names $name]
    
    # Если иконка не первая, меняем порядок
    if {$pos > 0} {
        set prev_name [lindex $names [expr {$pos - 1}]]
        set prev_data [dict get $pinned_icons $prev_name]
        set curr_data [dict get $pinned_icons $name]
        
        # Создаем новый словарь с обновленным порядком
        set new_pinned [dict create]
        
        foreach item_name [dict keys $pinned_icons] {
            if {$item_name eq $prev_name} {
                dict set new_pinned $name $curr_data
            } elseif {$item_name eq $name} {
                dict set new_pinned $prev_name $prev_data
            } else {
                dict set new_pinned $item_name [dict get $pinned_icons $item_name]
            }
        }
        
        # Обновляем глобальный словарь
        set pinned_icons $new_pinned
        
        # Сохраняем и обновляем отображение
        save_pinned_icons
        display_icons "pinned_only"
        
        # Обновляем настройки, если они открыты
        if {[winfo exists .settings]} {
            destroy .settings.frame.pinned
            add_pinned_tab_to_settings
        }
    }
}

# Перемещение закрепленной иконки вправо
proc move_icon_right {name} {
    global pinned_icons
    
    # Получаем список имен
    set names [dict keys $pinned_icons]
    set pos [lsearch -exact $names $name]
    
    # Если иконка не последняя, меняем порядок
    if {$pos < [expr {[llength $names] - 1}]} {
        set next_name [lindex $names [expr {$pos + 1}]]
        set next_data [dict get $pinned_icons $next_name]
        set curr_data [dict get $pinned_icons $name]
        
        # Создаем новый словарь с обновленным порядком
        set new_pinned [dict create]
        
        foreach item_name [dict keys $pinned_icons] {
            if {$item_name eq $name} {
                dict set new_pinned $next_name $next_data
            } elseif {$item_name eq $next_name} {
                dict set new_pinned $name $curr_data
            } else {
                dict set new_pinned $item_name [dict get $pinned_icons $item_name]
            }
        }
        
        # Обновляем глобальный словарь
        set pinned_icons $new_pinned
        
        # Сохраняем и обновляем отображение
        save_pinned_icons
        display_icons "pinned_only"
        
        # Обновляем настройки, если они открыты
        if {[winfo exists .settings]} {
            destroy .settings.frame.pinned
            add_pinned_tab_to_settings
        }
    }
}

#p5

# Функция для отображения контекстного меню с уникальными именами
proc show_button_menu {button name exec_cmd desktop_file} {
    global main config menu_list
    
    # Получаем координаты кнопки для размещения меню
    set button_x [winfo rootx $button]
    set button_y [winfo rooty $button]
    set button_width [winfo width $button]
    set button_height [winfo height $button]
    
    # Создаем уникальное имя для меню
    set menu_id [clock milliseconds]
    set menu_path ".button_menu_$menu_id"
    
    # Уничтожаем все предыдущие меню
    foreach old_menu [winfo children .] {
        if {[string match ".button_menu_*" $old_menu]} {
            catch {destroy $old_menu}
        }
    }
    
    # Создаем новое меню
    set m [menu $menu_path -tearoff 0]
    
    # Проверяем, закреплена ли иконка
    if {[is_pinned $name]} {
        $m add command -label "Открепить" -command [list unpin_menu_item $name $menu_path]
    } else {
        $m add command -label "Закрепить" -command [list pin_menu_item $button $name $exec_cmd $desktop_file $menu_path]
    }
    
    $m add separator
    $m add command -label "Заменить иконку" -command [list change_icon_menu_item $button $name $exec_cmd $desktop_file $menu_path]
    
    # Показываем меню рядом с кнопкой
    tk_popup $m [expr {$button_x + $button_width/2}] [expr {$button_y + $button_height/2}]
}

# Функции-обертки для команд меню
proc pin_menu_item {button name exec_cmd desktop_file menu_path} {
    # Уничтожаем меню перед выполнением действия
    if {[winfo exists $menu_path]} {
        # Отложенное уничтожение, чтобы меню успело закрыться корректно
        after 100 [list catch [list destroy $menu_path]]
    }
    pin_icon $button $name $exec_cmd $desktop_file
}

proc unpin_menu_item {name menu_path} {
    # Уничтожаем меню перед выполнением действия
    if {[winfo exists $menu_path]} {
        # Отложенное уничтожение, чтобы меню успело закрыться корректно
        after 100 [list catch [list destroy $menu_path]]
    }
    unpin_icon $name
}

proc change_icon_menu_item {button name exec_cmd desktop_file menu_path} {
    # Уничтожаем меню перед выполнением действия
    if {[winfo exists $menu_path]} {
        # Отложенное уничтожение, чтобы меню успело закрыться корректно
        after 100 [list catch [list destroy $menu_path]]
    }
    change_icon $button $name $exec_cmd $desktop_file
}

# Обработка кнопок и долгого нажатия
proc handle_button_press {button exec_cmd name desktop_file} {
    global press_time long_press_id
    set press_time [clock milliseconds]
    set long_press_id [after 500 [list handle_long_press $button $name $exec_cmd $desktop_file]]
}

proc handle_long_press {button name exec_cmd desktop_file} {
    global press_time long_press_id
    if {[info exists long_press_id]} {
        # Показываем контекстное меню
        show_button_menu $button $name $exec_cmd $desktop_file
        unset long_press_id
    }
}

proc handle_button_release {button exec_cmd desktop_file} {
    global press_time long_press_id cached_terminal_cmd
    if {[info exists long_press_id]} {
        after cancel $long_press_id
        unset long_press_id
        if {[expr {[clock milliseconds] - $press_time}] < 500} {
            set info [parse_desktop_file $desktop_file]
            if {[dict get $info terminal] eq "true"} {
                # Поиск доступного терминала, если еще не кэширован
                if {$cached_terminal_cmd eq ""} {
                    foreach term {xterm uxterm lxterminal xfce4-terminal gnome-terminal terminator konsole} {
                        if {[auto_execok $term] ne ""} {
                            set cached_terminal_cmd $term
                            break
                        }
                    }
                }
                
                if {$cached_terminal_cmd eq ""} {
                    tk_messageBox -icon error -title "Ошибка" -message "Не найден терминал для запуска приложения!"
                    return
                }
                
                set cmd_args ""
                switch $cached_terminal_cmd {
                    "xterm" - "uxterm" {set cmd_args "-e sh -c \"$exec_cmd ; exec bash\""}
                    "lxterminal" - "konsole" {set cmd_args "-e sh -c \"$exec_cmd ; read -p 'Нажмите Enter для закрытия...'\""}
                    "xfce4-terminal" {set cmd_args "-e \"$exec_cmd ; read -p 'Нажмите Enter для закрытия...'\""}
                    "gnome-terminal" {set cmd_args "-- sh -c \"$exec_cmd ; read -p 'Нажмите Enter для закрытия...'\""}
                    "terminator" {set cmd_args "-e \"sh -c '$exec_cmd ; read -p \\\"Нажмите Enter для закрытия...\\\"'\""}
                    default {set cmd_args "-e sh -c \"$exec_cmd ; exec bash\""}
                }
                catch {eval exec $cached_terminal_cmd $cmd_args &}
            } else {
                catch {exec {*}$exec_cmd &}
            }
        }
    }
}

#p6

# Переменные для окна настроек
set bg_right_var ""
set selection_var ""
set font_color_var ""
set current_font ""
set current_size 9
set padding_var 10

# Переменная для хранения выбранной закрепленной иконки
set selected_pinned_icon ""

# Функция очистки кэша перед обновлением
proc clear_cache_directories {} {
    global BUTTON_DIR ICON_CACHE_DIR categories
    
    # Очищаем директории кэша, но сохраняем структуру
    foreach {cat _} $categories {
        set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
        if {[file exists $cat_dir]} {
            foreach file [glob -nocomplain -directory $cat_dir "*.desktop"] {
                file delete $file
            }
        }
    }
    
    # Сбрасываем глобальные переменные кэша
    set ::cache_desktop_files [dict create]
    set ::cache_app_info [dict create]
    set ::button_to_desktop [dict create]
    set ::search_terms [dict create]
}

# Функция для отображения закрепленных иконок
proc show_pinned_icons {} {
    global main
    
    # Проверка, что главное окно существует
    if {![info exists main] || ![winfo exists $main]} {
        return
    }
    
    # Отображаем иконки в режиме "только закрепленные"
    display_icons "pinned_only"
}

# Модифицированная функция для перемещения иконки влево (выше) в списке закрепленных
proc move_icon_left {name} {
    global pinned_icons
    
    if {![dict exists $pinned_icons $name]} {
        return
    }
    
    # Получаем текущие данные иконки
    set icon_data [dict get $pinned_icons $name]
    
    # Получаем все ключи (имена иконок) в том же порядке
    set keys [dict keys $pinned_icons]
    set pos [lsearch -exact $keys $name]
    
    # Проверяем, можно ли переместить влево
    if {$pos <= 0} {
        return
    }
    
    # Получаем имя иконки слева
    set left_name [lindex $keys [expr {$pos - 1}]]
    set left_data [dict get $pinned_icons $left_name]
    
    # Создаем новый словарь в нужном порядке
    set new_pinned_icons [dict create]
    
    set i 0
    foreach key $keys {
        if {$i == $pos - 1} {
            # Вставляем текущую иконку перед левой
            dict set new_pinned_icons $name $icon_data
            dict set new_pinned_icons $left_name $left_data
            incr i 2
            continue
        } elseif {$i == $pos} {
            # Пропускаем, так как уже вставили
            incr i
            continue
        }
        
        # Копируем остальные иконки без изменений
        dict set new_pinned_icons $key [dict get $pinned_icons $key]
        incr i
    }
    
    # Обновляем глобальный словарь
    set pinned_icons $new_pinned_icons
    
    # Сохраняем изменения
    save_pinned_icons
    
    # Обновляем отображение иконок в главном окне
    if {[info exists ::main] && [winfo exists $::main]} {
        display_icons "pinned_only"
    }
}

# Модифицированная функция для перемещения иконки вправо (ниже) в списке закрепленных
proc move_icon_right {name} {
    global pinned_icons
    
    if {![dict exists $pinned_icons $name]} {
        return
    }
    
    # Получаем текущие данные иконки
    set icon_data [dict get $pinned_icons $name]
    
    # Получаем все ключи (имена иконок) в том же порядке
    set keys [dict keys $pinned_icons]
    set pos [lsearch -exact $keys $name]
    
    # Проверяем, можно ли переместить вправо
    if {$pos >= [expr {[llength $keys] - 1}]} {
        return
    }
    
    # Получаем имя иконки справа
    set right_name [lindex $keys [expr {$pos + 1}]]
    set right_data [dict get $pinned_icons $right_name]
    
    # Создаем новый словарь в нужном порядке
    set new_pinned_icons [dict create]
    
    set i 0
    foreach key $keys {
        if {$i == $pos} {
            # Вставляем правую иконку перед текущей
            dict set new_pinned_icons $right_name $right_data
            dict set new_pinned_icons $name $icon_data
            incr i 2
            continue
        } elseif {$i == $pos + 1} {
            # Пропускаем, так как уже вставили
            incr i
            continue
        }
        
        # Копируем остальные иконки без изменений
        dict set new_pinned_icons $key [dict get $pinned_icons $key]
        incr i
    }
    
    # Обновляем глобальный словарь
    set pinned_icons $new_pinned_icons
    
    # Сохраняем изменения
    save_pinned_icons
    
    # Обновляем отображение иконок в главном окне
    if {[info exists ::main] && [winfo exists $::main]} {
        display_icons "pinned_only"
    }
}

# Функция для открытия менеджера закрепленных иконок
proc open_pinned_manager {} {
    global config pinned_icons
    
    # Проверяем, не открыт ли уже менеджер
    if {[winfo exists .pinned_manager]} {
        focus .pinned_manager
        return
    }
    
    # Создаем новое немодальное окно
    toplevel .pinned_manager
    wm title .pinned_manager "Управление закрепленными иконками"
    
    # Устанавливаем размер и положение
    set screen_width [winfo screenwidth .]
    set screen_height [winfo screenheight .]
    set win_width 500
    set win_height 400
    set x [expr {int(($screen_width - $win_width) / 2)}]
    set y [expr {int(($screen_height - $win_height) / 2)}]
    wm geometry .pinned_manager ${win_width}x${win_height}+${x}+${y}
    
    # Создаем фрейм для содержимого
    frame .pinned_manager.frame -padx 10 -pady 10 -background [dict get $config Layout bg_right]
    pack .pinned_manager.frame -fill both -expand true
    
    # Заголовок
    label .pinned_manager.frame.title -text "Управление закрепленными иконками" -font "TkDefaultFont 14 bold" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .pinned_manager.frame.title -pady 10
    
    # Если нет закрепленных иконок, выводим сообщение
    if {[dict size $pinned_icons] == 0} {
        label .pinned_manager.frame.empty -text "Нет закрепленных иконок" \
              -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
        pack .pinned_manager.frame.empty -pady 5
        
        # Кнопка закрытия
        button .pinned_manager.frame.close -text "Закрыть" -command {destroy .pinned_manager} \
               -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
        pack .pinned_manager.frame.close -side bottom -pady 10
        
        return
    }
    
    # Создаем фрейм для кнопок управления
    frame .pinned_manager.frame.controls -background [dict get $config Layout bg_right]
    pack .pinned_manager.frame.controls -fill x -pady 5
    
    # Инструкции по использованию
    label .pinned_manager.frame.controls.help -text "Выберите иконку и используйте стрелки для изменения позиции" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color] \
          -font "TkDefaultFont 8" -justify left
    pack .pinned_manager.frame.controls.help -fill x -pady 5
    
    # Кнопки для перемещения вверх/вниз (изначально неактивны)
    frame .pinned_manager.frame.controls.buttons -background [dict get $config Layout bg_right]
    pack .pinned_manager.frame.controls.buttons -fill x
    
    button .pinned_manager.frame.controls.buttons.up -text "↑ Переместить вверх" -state disabled \
           -command {move_selected_icon_up} -background [dict get $config Layout bg_right] \
           -foreground [dict get $config Layout font_color]
    pack .pinned_manager.frame.controls.buttons.up -side left -padx 5 -pady 5
    
    button .pinned_manager.frame.controls.buttons.down -text "↓ Переместить вниз" -state disabled \
           -command {move_selected_icon_down} -background [dict get $config Layout bg_right] \
           -foreground [dict get $config Layout font_color]
    pack .pinned_manager.frame.controls.buttons.down -side left -padx 5 -pady 5
    
    button .pinned_manager.frame.controls.buttons.unpin -text "Открепить" -state disabled \
          -command {unpin_selected_icon} -background [dict get $config Layout bg_right] \
          -foreground [dict get $config Layout font_color]
   pack .pinned_manager.frame.controls.buttons.unpin -side right -padx 5 -pady 5
    
    # Создаем фрейм со скроллингом для списка иконок
    frame .pinned_manager.frame.list_frame -background [dict get $config Layout bg_right] -borderwidth 1 -relief sunken
    pack .pinned_manager.frame.list_frame -fill both -expand true -pady 5
    
    canvas .pinned_manager.frame.list_frame.canvas -background [dict get $config Layout bg_right] \
           -yscrollcommand ".pinned_manager.frame.list_frame.scroll set"
    scrollbar .pinned_manager.frame.list_frame.scroll -orient vertical \
             -command ".pinned_manager.frame.list_frame.canvas yview"
    
    pack .pinned_manager.frame.list_frame.scroll -side right -fill y
    pack .pinned_manager.frame.list_frame.canvas -side left -fill both -expand true
    
    # Создаем фрейм внутри канваса для элементов списка
    frame .pinned_manager.frame.list_frame.canvas.items -background [dict get $config Layout bg_right]
    .pinned_manager.frame.list_frame.canvas create window 0 0 -anchor nw -window .pinned_manager.frame.list_frame.canvas.items
    
    # Добавляем каждую закрепленную иконку в список
    set i 0
    dict for {name data} $pinned_icons {
        lassign $data exec_cmd desktop_file
        
        # Создаем фрейм для элемента списка
        frame .pinned_manager.frame.list_frame.canvas.items.item$i -background [dict get $config Layout bg_right] \
              -borderwidth 1 -relief solid -padx 5 -pady 5
        pack .pinned_manager.frame.list_frame.canvas.items.item$i -fill x -pady 2
        
        # Название иконки с возможностью выбора (радиокнопка)
        radiobutton .pinned_manager.frame.list_frame.canvas.items.item$i.radio -text $name -value $name \
                   -variable ::selected_pinned_icon -background [dict get $config Layout bg_right] \
                   -foreground [dict get $config Layout font_color] -anchor w -width 30 \
                   -command update_pinned_controls
        pack .pinned_manager.frame.list_frame.canvas.items.item$i.radio -side left -padx 5
        
        incr i
    }
    
    # Настройка размеров и скроллинга канваса
    bind .pinned_manager.frame.list_frame.canvas <Configure> {
        .pinned_manager.frame.list_frame.canvas configure -scrollregion [.pinned_manager.frame.list_frame.canvas bbox all]
        .pinned_manager.frame.list_frame.canvas itemconfigure all -width %w
    }
    
    # Поддержка прокрутки колесом мыши
    bind .pinned_manager.frame.list_frame.canvas <MouseWheel> {
        .pinned_manager.frame.list_frame.canvas yview scroll [expr {-%D / 120}] units
    }
    bind .pinned_manager.frame.list_frame.canvas <Button-4> {
        .pinned_manager.frame.list_frame.canvas yview scroll -1 units
    }
    bind .pinned_manager.frame.list_frame.canvas <Button-5> {
        .pinned_manager.frame.list_frame.canvas yview scroll 1 units
    }
    
    # Обновляем размеры канваса после создания всех элементов
    update idletasks
    .pinned_manager.frame.list_frame.canvas configure -scrollregion [.pinned_manager.frame.list_frame.canvas bbox all] \
                                                     -width [winfo width .pinned_manager.frame.list_frame] \
                                                     -height [expr {min(300, [winfo height .pinned_manager.frame.list_frame.canvas.items])}]
    
    # Кнопка закрытия
    button .pinned_manager.frame.close -text "Закрыть" -command {destroy .pinned_manager} \
           -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .pinned_manager.frame.close -side bottom -pady 10
}

# Функция обновления состояния кнопок управления
proc update_pinned_controls {} {
    global selected_pinned_icon pinned_icons
    
    if {$selected_pinned_icon eq "" || ![dict exists $pinned_icons $selected_pinned_icon]} {
        # Если иконка не выбрана или уже не существует, деактивируем кнопки
        .pinned_manager.frame.controls.buttons.up configure -state disabled
        .pinned_manager.frame.controls.buttons.down configure -state disabled
        .pinned_manager.frame.controls.buttons.unpin configure -state disabled
        return
    }
    
    # Активируем кнопку "Открепить"
    .pinned_manager.frame.controls.buttons.unpin configure -state normal
    
    # Получаем список имен и позицию выбранной иконки
    set names [dict keys $pinned_icons]
    set pos [lsearch -exact $names $selected_pinned_icon]
    
    # Активируем/деактивируем кнопки в зависимости от позиции
    if {$pos == 0} {
        .pinned_manager.frame.controls.buttons.up configure -state disabled
    } else {
        .pinned_manager.frame.controls.buttons.up configure -state normal
    }
    
    if {$pos == [expr {[llength $names] - 1}]} {
        .pinned_manager.frame.controls.buttons.down configure -state disabled
    } else {
        .pinned_manager.frame.controls.buttons.down configure -state normal
    }
}

# Функция для перемещения выбранной иконки вверх
proc move_selected_icon_up {} {
    global selected_pinned_icon
    
    if {$selected_pinned_icon ne ""} {
        move_icon_left $selected_pinned_icon
        
        # Обновляем окно
        destroy .pinned_manager
        open_pinned_manager
        
        # Восстанавливаем выбор
        if {[winfo exists .pinned_manager.frame.list_frame.canvas.items]} {
            set i 0
            dict for {name _} $::pinned_icons {
                if {$name eq $selected_pinned_icon} {
                    .pinned_manager.frame.list_frame.canvas.items.item$i.radio invoke
                    break
                }
                incr i
            }
        }
    }
}

# Функция для перемещения выбранной иконки вниз
proc move_selected_icon_down {} {
    global selected_pinned_icon
    
    if {$selected_pinned_icon ne ""} {
        move_icon_right $selected_pinned_icon
        
        # Обновляем окно
        destroy .pinned_manager
        open_pinned_manager
        
        # Восстанавливаем выбор
        if {[winfo exists .pinned_manager.frame.list_frame.canvas.items]} {
            set i 0
            dict for {name _} $::pinned_icons {
                if {$name eq $selected_pinned_icon} {
                    .pinned_manager.frame.list_frame.canvas.items.item$i.radio invoke
                    break
                }
                incr i
            }
        }
    }
}

# Функция для открепления выбранной иконки
proc unpin_selected_icon {} {
    global selected_pinned_icon
    
    if {$selected_pinned_icon ne ""} {
        unpin_icon $selected_pinned_icon
        set selected_pinned_icon ""
        
        # Обновляем окно
        destroy .pinned_manager
        open_pinned_manager
    }
}

# Модифицированная функция открытия окна настроек
proc open_settings_window {} {
    global config bg_right_var selection_var font_color_var current_font current_size padding_var
    
    if {[winfo exists .settings]} {
        focus .settings
        return
    }
    
    # Инициализируем глобальные переменные
    set bg_right_var [dict get $config Layout bg_right]
    set selection_var [dict get $config Layout selection_color]
    set font_color_var [dict get $config Layout font_color]
    set padding_var [dict get $config Layout button_padding]
    
    # Получаем текущий шрифт
    set current_font "TkDefaultFont"
    if {[dict exists $config Layout font_family]} {
        set current_font [dict get $config Layout font_family]
    } else {
        # Добавляем в конфиг, если отсутствует
        dict set config Layout font_family $current_font
    }
    
    # Получаем текущий размер шрифта
    set current_size 9
    if {[dict exists $config Layout font_size]} {
        set current_size [dict get $config Layout font_size]
    } else {
        # Добавляем в конфиг, если отсутствует
        dict set config Layout font_size $current_size
    }
    
    toplevel .settings
    wm title .settings "Настройки интерфейса"
    
    # Устанавливаем размер и положение
    set screen_width [winfo screenwidth .]
    set screen_height [winfo screenheight .]
    set win_width 400
    # Увеличиваем высоту для дополнительных настроек
    set win_height 650
    set x [expr {int(($screen_width - $win_width) / 2)}]
    set y [expr {int(($screen_height - $win_height) / 2)}]
    wm geometry .settings ${win_width}x${win_height}+${x}+${y}
    
    # Фрейм для настроек
    frame .settings.frame -padx 10 -pady 10 -background [dict get $config Layout bg_right]
    pack .settings.frame -fill both -expand true
    
    # Заголовок
    label .settings.frame.title -text "Настройки интерфейса" -font "TkDefaultFont 14 bold" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.title -pady 10
    
    # Настройки цветов
    labelframe .settings.frame.colors -text "Цвета" -background [dict get $config Layout bg_right] \
              -foreground [dict get $config Layout font_color] -padx 5 -pady 5
    pack .settings.frame.colors -fill x -pady 5
    
    # Цвет фона основного окна
    frame .settings.frame.colors.bg_right -background [dict get $config Layout bg_right]
    pack .settings.frame.colors.bg_right -fill x -pady 3
    
    label .settings.frame.colors.bg_right.label -text "Цвет фона окна:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.colors.bg_right.label -side left -padx 5
    
    entry .settings.frame.colors.bg_right.entry -textvariable bg_right_var -width 10
    pack .settings.frame.colors.bg_right.entry -side left -padx 5
    
    button .settings.frame.colors.bg_right.pick -text "..." -command {
        set color [tk_chooseColor -initialcolor $bg_right_var -title "Выбор цвета фона окна"]
        if {$color ne ""} {
            set bg_right_var $color
            .settings.frame.colors.bg_right.entry delete 0 end
            .settings.frame.colors.bg_right.entry insert 0 $color
        }
    }
    pack .settings.frame.colors.bg_right.pick -side left -padx 5
    
    # Цвет фона поиска
    frame .settings.frame.colors.selection -background [dict get $config Layout bg_right]
    pack .settings.frame.colors.selection -fill x -pady 3
    
    label .settings.frame.colors.selection.label -text "Цвет фона поиска:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.colors.selection.label -side left -padx 5
    
    entry .settings.frame.colors.selection.entry -textvariable selection_var -width 10
    pack .settings.frame.colors.selection.entry -side left -padx 5
    
    button .settings.frame.colors.selection.pick -text "..." -command {
        set color [tk_chooseColor -initialcolor $selection_var -title "Выбор цвета фона поиска"]
        if {$color ne ""} {
            set selection_var $color
            .settings.frame.colors.selection.entry delete 0 end
            .settings.frame.colors.selection.entry insert 0 $color
        }
    }
    pack .settings.frame.colors.selection.pick -side left -padx 5
    
    # Цвет шрифта
    frame .settings.frame.colors.font_color -background [dict get $config Layout bg_right]
    pack .settings.frame.colors.font_color -fill x -pady 3
    
    label .settings.frame.colors.font_color.label -text "Цвет шрифта:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.colors.font_color.label -side left -padx 5
    
    entry .settings.frame.colors.font_color.entry -textvariable font_color_var -width 10
    pack .settings.frame.colors.font_color.entry -side left -padx 5
    
    button .settings.frame.colors.font_color.pick -text "..." -command {
        set color [tk_chooseColor -initialcolor $font_color_var -title "Выбор цвета шрифта"]
        if {$color ne ""} {
            set font_color_var $color
            .settings.frame.colors.font_color.entry delete 0 end
            .settings.frame.colors.font_color.entry insert 0 $color
        }
    }
    pack .settings.frame.colors.font_color.pick -side left -padx 5
    
    # Настройки шрифта
    labelframe .settings.frame.font -text "Шрифт" -background [dict get $config Layout bg_right] \
              -foreground [dict get $config Layout font_color] -padx 5 -pady 5
    pack .settings.frame.font -fill x -pady 5
    
    # Выбор шрифта
    frame .settings.frame.font.family -background [dict get $config Layout bg_right]
    pack .settings.frame.font.family -fill x -pady 3
    
    label .settings.frame.font.family.label -text "Шрифт:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.font.family.label -side left -padx 5
    
    # Получаем список доступных шрифтов
    set available_fonts [font families]
    if {[llength $available_fonts] == 0} {
        set available_fonts [list "TkDefaultFont" "TkTextFont" "TkFixedFont"]
    }
    
    ttk::combobox .settings.frame.font.family.combo -values $available_fonts -width 20 -textvariable current_font
    .settings.frame.font.family.combo set $current_font
    pack .settings.frame.font.family.combo -side left -padx 5
    
    # Размер шрифта
    frame .settings.frame.font.size -background [dict get $config Layout bg_right]
    pack .settings.frame.font.size -fill x -pady 3
    
    label .settings.frame.font.size.label -text "Размер шрифта:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.font.size.label -side left -padx 5
    
    ttk::spinbox .settings.frame.font.size.spin -from 8 -to 20 -width 5 -textvariable current_size
    .settings.frame.font.size.spin set $current_size
    pack .settings.frame.font.size.spin -side left -padx 5
    
    # Настройки отображения
    labelframe .settings.frame.display -text "Отображение" -background [dict get $config Layout bg_right] \
              -foreground [dict get $config Layout font_color] -padx 5 -pady 5
    pack .settings.frame.display -fill x -pady 5
    
    # Отступ между иконками
    frame .settings.frame.display.padding -background [dict get $config Layout bg_right]
    pack .settings.frame.display.padding -fill x -pady 3
    
    label .settings.frame.display.padding.label -text "Отступ между иконками:" \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.display.padding.label -side left -padx 5
    
    ttk::spinbox .settings.frame.display.padding.spin -from 5 -to 50 -width 5 -textvariable padding_var
    .settings.frame.display.padding.spin set $padding_var
    pack .settings.frame.display.padding.spin -side left -padx 5
    
    # Добавляем секцию для обновления кэша
    labelframe .settings.frame.cache -text "Управление кэшем" -background [dict get $config Layout bg_right] \
              -foreground [dict get $config Layout font_color] -padx 5 -pady 5
    pack .settings.frame.cache -fill x -pady 5
    
    # Кнопка обновления кэша
    button .settings.frame.cache.update -text "Обновить кэш приложений" -command update_cache_gui \
           -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.cache.update -fill x -pady 5
    
    # Добавляем описание
    label .settings.frame.cache.desc -text "Обновление кэша перестроит список всех доступных приложений\nи обновит их иконки. Это может занять некоторое время." \
          -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color] \
          -justify left -font "TkDefaultFont 8"
    pack .settings.frame.cache.desc -fill x -pady 5
    
    # Добавляем кнопку для открытия окна управления закрепленными иконками
    labelframe .settings.frame.pinned_btn -text "Закрепленные иконки" -background [dict get $config Layout bg_right] \
              -foreground [dict get $config Layout font_color] -padx 5 -pady 5
    pack .settings.frame.pinned_btn -fill x -pady 5
    
    button .settings.frame.pinned_btn.open -text "Управление закрепленными иконками" -command open_pinned_manager \
           -background [dict get $config Layout bg_right] -foreground [dict get $config Layout font_color]
    pack .settings.frame.pinned_btn.open -fill x -pady 5
    
    # Кнопки действий
    frame .settings.frame.buttons -background [dict get $config Layout bg_right]
    pack .settings.frame.buttons -fill x -pady 10
    
    button .settings.frame.buttons.apply -text "Применить" -command {
        # Сохраняем настройки
        dict set ::config Layout bg_right $::bg_right_var
        dict set ::config Layout selection_color $::selection_var
        dict set ::config Layout font_color $::font_color_var
        dict set ::config Layout font_family $::current_font
        dict set ::config Layout font_size $::current_size
        dict set ::config Layout button_padding $::padding_var
        
        # Применяем изменения
        apply_colors
        apply_font_settings
        save_config
        
        # Закрываем окно настроек
        destroy .settings
        
        # Обновляем интерфейс
        display_icons "pinned_only"
        if {[winfo exists $::main.results.canvas]} {
            update_canvas_size $::main.results.canvas
        }
    }
    pack .settings.frame.buttons.apply -side right -padx 5
    
    button .settings.frame.buttons.cancel -text "Отмена" -command {destroy .settings}
    pack .settings.frame.buttons.cancel -side right -padx 5
    
    button .settings.frame.buttons.reset -text "Сбросить" -command {
        # Сбрасываем настройки к дефолтным значениям
        dict set ::config Layout bg_right "#ffffff"
        dict set ::config Layout bg_left "#d9d9d9"
        dict set ::config Layout selection_color "#87CEEB"
        dict set ::config Layout font_color "#000000"
        dict set ::config Layout cat_font_color "#000000"
        dict set ::config Layout button_border_color "#808080"
        dict set ::config Layout button_padding 10
        dict set ::config Layout icon_scale 1.0
        dict set ::config Layout search_entry_border_width 0
        dict set ::config Layout font_family "TkDefaultFont"
        dict set ::config Layout font_size 9
        
        # Обновляем поля ввода
        set ::bg_right_var [dict get $::config Layout bg_right]
        set ::selection_var [dict get $::config Layout selection_color]
        set ::font_color_var [dict get $::config Layout font_color]
        set ::current_font [dict get $::config Layout font_family]
        set ::current_size [dict get $::config Layout font_size]
        set ::padding_var [dict get $::config Layout button_padding]
        
        # Обновляем значения в виджетах
        .settings.frame.colors.bg_right.entry delete 0 end
        .settings.frame.colors.bg_right.entry insert 0 $::bg_right_var
        
        .settings.frame.colors.selection.entry delete 0 end
        .settings.frame.colors.selection.entry insert 0 $::selection_var
        
        .settings.frame.colors.font_color.entry delete 0 end
        .settings.frame.colors.font_color.entry insert 0 $::font_color_var
        
        .settings.frame.font.family.combo set $::current_font
        .settings.frame.font.size.spin set $::current_size
        
        .settings.frame.display.padding.spin set $::padding_var
        
        # Применяем изменения
        apply_colors
        apply_font_settings
        save_config
    }
    pack .settings.frame.buttons.reset -side left -padx 5
}

#p7

# Улучшенная функция обновления кэша
proc update_cache_gui {} {
    global argv0 main
    
    # Показываем окно прогресса
    set progress [toplevel .update_progress]
    wm title $progress "Обновление кэша"
    wm attributes $progress -topmost 1
    
    set screen_width [winfo screenwidth .]
    set screen_height [winfo screenheight .]
    set win_width 400
    set win_height 200
    set x [expr {($screen_width - $win_width) / 2}]
    set y [expr {($screen_height - $win_height) / 2}]
    wm geometry $progress ${win_width}x${win_height}+${x}+${y}
    
    # Используем цвета из конфига
    set bg_color [dict get $::config Layout bg_right]
    set fg_color [dict get $::config Layout font_color]
    
    $progress configure -background $bg_color
    
    frame $progress.content -background $bg_color -borderwidth 1 -relief groove
    pack $progress.content -expand true -fill both -padx 10 -pady 10
    
    label $progress.content.label -text "Обновление кэша приложений...\nЭто может занять некоторое время." \
        -background $bg_color -foreground $fg_color -font "TkDefaultFont 9"
    pack $progress.content.label -pady 5
    
    ttk::progressbar $progress.content.bar -mode indeterminate -maximum 100
    pack $progress.content.bar -fill x -pady 10
    $progress.content.bar start
    
    # Добавляем текстовое поле для статуса
    label $progress.content.status -text "Сканирование директорий с приложениями..." \
        -background $bg_color -foreground $fg_color -font "TkDefaultFont 8" -anchor w
    pack $progress.content.status -fill x -pady 5
    
    # Очищаем поисковую строку и результаты
    if {[winfo exists $main]} {
        if {[winfo exists $main.search.entry]} {
            $main.search.entry delete 0 end
        }
        hide_results_panel
    }
    
    # Обновляем отображение
    update idletasks
    
    # Запускаем обновление кэша прямо здесь вместо отдельного процесса
    after 100 {
        # Очищаем кэш
        clear_cache_directories
        
        # Пересоздаем структуру директорий
        create_directories
        
        # Запускаем построение кэша
        build_cache_in_place .update_progress.content.status .update_progress.content.bar
        
        # Закрываем окно прогресса
        if {[winfo exists .update_progress]} {
            destroy .update_progress
        }
        
        # Показываем сообщение об успешном обновлении
        tk_messageBox -icon info -title "Обновление кэша" \
            -message "Кэш приложений успешно обновлен."
            
        # Перезагружаем кэш в текущий сеанс
        load_icon_type_cache
        initialize_cache
        
        # Если открыт поиск с результатами, обновляем его
        if {$::results_visible && [winfo exists $::main.search.entry]} {
            set query [$::main.search.entry get]
            if {$query ne ""} {
                fuzzy_search $query "Все"
            }
        }
        
        # Обновляем закрепленные иконки
        show_pinned_icons
    }
}

# Функция для построения кэша непосредственно в текущем процессе
proc build_cache_in_place {{status_label ""} {progress_bar ""}} {
    global BUTTON_DIR ICON_CACHE_DIR categories button_to_desktop placeholder_icon config cache_desktop_files
    
    # Список директорий для сканирования
    set app_dirs {
        "/home/live/.local/share/applications" 
        "/usr/share/applications" 
        "/usr/local/share/applications"
    }
    
    # Обновляем статус
    if {$status_label ne "" && [winfo exists $status_label]} {
        $status_label configure -text "Сканирование директорий с приложениями..."
        update idletasks
    }
    
    # Сбор и обработка файлов .desktop
    set desktop_files {}
    foreach dir $app_dirs {
        if {[file exists $dir]} {
            set dir_files [glob -nocomplain -directory $dir "*.desktop"]
            lappend desktop_files {*}$dir_files
            
            # Обновляем статус
            if {$status_label ne "" && [winfo exists $status_label]} {
                $status_label configure -text "Найдено [llength $dir_files] файлов в $dir"
                update idletasks
            }
        }
    }
    
    set total_items [llength $desktop_files]
    if {$total_items == 0} {
        if {$status_label ne "" && [winfo exists $status_label]} {
            $status_label configure -text "Не найдено .desktop файлов"
        }
        return
    }
    
    # Переключаем прогресс-бар в детерминированный режим
    if {$progress_bar ne "" && [winfo exists $progress_bar]} {
        $progress_bar configure -mode determinate -maximum $total_items -value 0
    }
    
    set processed 0
    
    foreach file $desktop_files {
        # Обновляем прогресс
        incr processed
        if {$progress_bar ne "" && [winfo exists $progress_bar]} {
            $progress_bar configure -value $processed
        }
        
        # Обновляем статус с именем текущего файла
        if {$status_label ne "" && [winfo exists $status_label]} {
            $status_label configure -text "Обработка [file tail $file] ($processed из $total_items)"
            update idletasks
        }
        
        set info [parse_desktop_file $file]
        set name [dict get $info name]
        set exec_cmd [dict get $info exec]
        set icon [dict get $info icon]
        
        if {$name ne "" && $exec_cmd ne ""} {
            # Добавляем во все категории
            foreach {cat _} $categories {
                set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
                set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
                
                # Только для категории "Все" и для категорий, к которым принадлежит приложение
                if {$cat eq "Все" || [string match "*$cat*" [dict get $info categories]]} {
                    set desktop_filename [file tail $file]
                    set dest_file [file join $cat_dir $desktop_filename]
                    
                    # Проверяем, существует ли директория перед копированием
                    if {![file exists $cat_dir]} {file mkdir $cat_dir}
                    if {![file exists $icon_cat_dir]} {file mkdir $icon_cat_dir}
                    
                    # Копируем .desktop файл
                    file copy -force $file $dest_file
                    dict set button_to_desktop $name $dest_file
                    
                    # Обрабатываем иконку только один раз (для категории "Все")
                    if {$cat eq "Все" && $icon ne ""} {
                        set img [find_icon $icon $exec_cmd]
                        if {$img ne $placeholder_icon} {
                            # Проверяем, чтобы не было двойного расширения
                            set cache_base_name [string map {/ _} $name]
                            if {[string match "*.png" $cache_base_name]} {
                                set cache_file [file join $icon_cat_dir $cache_base_name]
                            } else {
                                set cache_file [file join $icon_cat_dir "$cache_base_name.png"]
                            }
                            catch {$img write $cache_file -format png}
                        }
                    }
                }
            }
        }
    }
    
    # Обновляем кэш для всех категорий
    foreach {cat _} $categories {
        set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
        dict set cache_desktop_files $cat [glob -nocomplain -directory $cat_dir "*.desktop"]
    }
    
    # Обновляем статус
    if {$status_label ne "" && [winfo exists $status_label]} {
        $status_label configure -text "Кэш обновлен: обработано $total_items приложений"
    }
    
    # Сохраняем кэш иконок
    save_icon_type_cache
}

# Смена иконки
proc change_icon {button name exec_cmd desktop_file} {
    global ICON_CACHE_DIR main config
    set scale [dict get $config Layout icon_scale]
    set new_size [expr {int(48 * $scale)}]
    if {$new_size < 48} {set new_size 48}

    set file_types {
        {{Image Files} {.png .jpg .jpeg .svg .xpm .ico}}
        {{All Files} *}
    }
    
    set new_icon_path [tk_getOpenFile -filetypes $file_types -title "Выберите новую иконку" -parent $main]
    if {$new_icon_path eq ""} {return}

    set cat [lindex [split [file dirname $desktop_file] "/"] end]
    set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
    
    # Проверяем, чтобы не было двойного расширения
    set cache_base_name [string map {/ _} $name]
    if {[string match "*.png" $cache_base_name]} {
        set cache_file [file join $icon_cat_dir $cache_base_name]
    } else {
        set cache_file [file join $icon_cat_dir "$cache_base_name.png"]
    }
    
    if {[file exists $cache_file]} {file delete $cache_file}
    
    if {[catch {
        if {[string match "*.ico" $new_icon_path]} {
            set temp_png "/tmp/temp_icon_[clock milliseconds].png"
            exec icotool -x -i 1 $new_icon_path -o $temp_png 2> /dev/null
            if {[file exists $temp_png]} {
                exec convert -background none -resize ${new_size}x${new_size}! $temp_png $cache_file 2> /dev/null
                file delete $temp_png
            }
        } else {
            exec convert -background none -resize ${new_size}x${new_size}! $new_icon_path $cache_file 2> /dev/null
        }
    } error_msg] == 0 && [file exists $cache_file]} {
        if {![catch {set new_img [image create photo -file $cache_file]}]} {
            $button configure -image $new_img
        }
    }
}

#p8
# Создание директорий
proc create_directories {} {
    global BUTTON_DIR ICON_CACHE_DIR categories
    if {![file exists $BUTTON_DIR]} {file mkdir $BUTTON_DIR}
    if {![file exists $ICON_CACHE_DIR]} {file mkdir $ICON_CACHE_DIR}
    foreach {cat _} $categories {
        set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
        set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
        if {![file exists $cat_dir]} {file mkdir $cat_dir}
        if {![file exists $icon_cat_dir]} {file mkdir $icon_cat_dir}
    }
}

proc create_placeholder_icon {} {
    global placeholder_icon config
    set scale [dict get $config Layout icon_scale]
    set new_size [expr {int(48 * $scale)}]
    if {$new_size < 48} {set new_size 48}
    
    # Создаем новую иконку-заполнитель
    set placeholder_icon [image create photo -width $new_size -height $new_size]
    set default_icon_path "/usr/share/icons/hicolor/48x48/apps/system-run.png"
    if {[file exists $default_icon_path]} {
        catch {
            set temp_img [image create photo -file $default_icon_path]
            $placeholder_icon copy $temp_img -shrink -to 0 0 $new_size $new_size
            image delete $temp_img
        }
    }
}

# Разбор .desktop файла
proc parse_desktop_file {file} {
    global cache_app_info
    if {[dict exists $cache_app_info $file]} {
        return [dict get $cache_app_info $file]
    }
    
    if {![file exists $file] || 
        ([file type $file] eq "link" && [file isdirectory [file readlink $file]]) ||
        ![file isfile $file]} {
        return {name "" exec "" icon "" categories "" terminal false}
    }
    
    set fd [open $file r]
    set data [read $fd]
    close $fd
    set name ""
    set exec_cmd ""
    set icon ""
    set categories ""
    set terminal "false"
    set nodisplay "false"
    set in_desktop_entry 0

    foreach line [split $data "\n"] {
        set line [string trim $line]
        if {$line eq "\[Desktop Entry\]"} {set in_desktop_entry 1; continue}
        if {[string match {\[*\]} $line]} {set in_desktop_entry 0; continue}
        if {!$in_desktop_entry} {continue}
        if {[string match "Name=*" $line]} {set name [string range $line 5 end]}
        if {[string match "Exec=*" $line]} {
            set exec_cmd [string trim [string range $line 5 end]]
            regsub -all {%[A-Za-z]} $exec_cmd "" exec_cmd
        }
        if {[string match "Icon=*" $line]} {set icon [string range $line 5 end]}
        if {[string match "Categories=*" $line]} {set categories [string range $line 11 end]}
        if {[string match "Terminal=*" $line]} {set terminal [string range $line 9 end]}
        if {[string match "NoDisplay=*" $line]} {set nodisplay [string range $line 10 end]}
    }
    
    if {$nodisplay eq "true" || $name eq ""} {
        return {name "" exec "" icon "" categories "" terminal false}
    }
    
    set info [list name $name exec [expr {$exec_cmd eq "" ? "echo 'Команда отсутствует'" : $exec_cmd}] icon $icon categories $categories terminal $terminal]
    dict set cache_app_info $file $info
    return $info
}

# Поиск иконки с улучшенной обработкой ошибок
proc find_icon {icon_name exec_cmd {is_symlink 0}} {
    global ICON_CACHE_DIR placeholder_icon config
    
    set scale [dict get $config Layout icon_scale]
    set new_size [expr {int(48 * $scale)}]
    if {$new_size < 48} {set new_size 48}

    set base_name [file tail $icon_name]
    set cached_icon [file join $ICON_CACHE_DIR "$base_name.png"]

    # Проверка на символическую ссылку
    if {$is_symlink} {
        set symlink_icon_path "/usr/share/icons/Adwaita/48x48/emblems/emblem-symbolic-link.png"
        if {[file exists $symlink_icon_path]} {
            set cached_icon [file join $ICON_CACHE_DIR "emblem-symbolic-link.png"]
            if {![file exists $cached_icon]} {
                if {![catch {
                    # Проверяем валидность файла перед преобразованием
                    if {[catch {exec file -b --mime-type $symlink_icon_path} mime_type] == 0 && 
                        [string match "image/*" $mime_type]} {
                        exec convert -background none -resize ${new_size}x${new_size}! $symlink_icon_path $cached_icon 2> /dev/null
                    }
                }]} {
                    if {[file exists $cached_icon]} {
                        set img [image create photo -file $cached_icon]
                        return $img
                    }
                }
            } elseif {[file exists $cached_icon]} {
                if {![catch {set img [image create photo -file $cached_icon]}]} {
                    return $img
                }
            }
        }
    }

    # Проверка кэша
    if {[file exists $cached_icon]} {
        if {![catch {set img [image create photo -file $cached_icon]}]} {
            return $img
        }
    }

    # Проверка прямого пути к иконке
    if {[file exists $icon_name]} {
        if {![catch {
            set img ""
            # Проверяем валидность файла
            if {[catch {exec file -b --mime-type $icon_name} mime_type] == 0 && 
                [string match "image/*" $mime_type]} {
                
                if {[string match "*.ico" $icon_name] || [file extension $icon_name] eq ".ico"} {
                    set temp_png "/tmp/temp_icon_[clock milliseconds].png"
                    if {[catch {exec icotool -x -i 1 $icon_name -o $temp_png 2> /dev/null}] == 0 && 
                        [file exists $temp_png]} {
                        exec convert -background none -resize ${new_size}x${new_size}! $temp_png $cached_icon 2> /dev/null
                        file delete $temp_png
                        if {[file exists $cached_icon]} {
                            set img [image create photo -file $cached_icon]
                        }
                    }
                } else {
                    exec convert -background none -resize ${new_size}x${new_size}! $icon_name $cached_icon 2> /dev/null
                    if {[file exists $cached_icon]} {
                        set img [image create photo -file $cached_icon]
                    }
                }
                if {$img ne ""} {
                    return $img
                }
            }
        }]} {
            # Обработка ошибки скрыта
        }
    }
    
    # Особая обработка для PWA_similar папки
    set pwa_icon_dir "/home/live/.local/bin/pwa_similar/icons"
    if {[file exists $pwa_icon_dir]} {
        foreach fmt {".png" ".svg" ".xpm" ".jpg" ".jpeg"} {
            set pwa_icon_path [file join $pwa_icon_dir "$base_name$fmt"]
            if {[file exists $pwa_icon_path]} {
                if {![catch {
                    # Проверяем валидность файла
                    if {[catch {exec file -b --mime-type $pwa_icon_path} mime_type] == 0 && 
                        [string match "image/*" $mime_type]} {
                        exec convert -background none -resize ${new_size}x${new_size}! $pwa_icon_path $cached_icon 2> /dev/null
                        if {[file exists $cached_icon]} {
                            set img [image create photo -file $cached_icon]
                            return $img
                        }
                    }
                }]} {
                    # Обработка ошибки скрыта
                }
            }
        }
    }
    
    # Поиск в системных каталогах иконок
    set icon_dirs {"/usr/share/icons" "/usr/local/share/icons" "/usr/share/pixmaps" "/home/live/.icons"}
    set themes {"hicolor" "Adwaita" "gnome"}
    catch {
        set theme [exec gsettings get org.gnome.desktop.interface icon-theme]
        set theme [string trim $theme "'"]
        if {$theme ne ""} {linsert $themes 0 $theme}
    }
    set sizes {"48x48" "64x64" "128x128" "32x32" "scalable"}
    set formats {".png" ".svg" ".xpm" ".jpg" ".jpeg"}

    foreach theme $themes {
        foreach dir $icon_dirs {
            foreach size $sizes {
                foreach fmt $formats {
                    set icon_path "$dir/$theme/$size/apps/$base_name$fmt"
                    if {[file exists $icon_path]} {
                        if {![catch {
                            # Проверяем валидность файла
                            if {[catch {exec file -b --mime-type $icon_path} mime_type] == 0 && 
                                [string match "image/*" $mime_type]} {
                                exec convert -background none -resize ${new_size}x${new_size}! $icon_path $cached_icon 2> /dev/null
                                if {[file exists $cached_icon]} {
                                    set img [image create photo -file $cached_icon]
                                    return $img
                                }
                            }
                        }]} {
                            # Обработка ошибки скрыта
                        }
                    }
                }
            }
        }
    }
    
    return $placeholder_icon
}

# Удаление кнопки
proc delete_button {button name desktop_file canvas} {
    global ICON_CACHE_DIR button_to_desktop main search_terms
    
    if {[file exists $desktop_file]} {file delete $desktop_file}
    set cat [lindex [split [file dirname $desktop_file] "/"] end]
    set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
    
    # Проверяем, чтобы не было двойного расширения
    set cache_base_name [string map {/ _} $name]
    if {[string match "*.png" $cache_base_name]} {
        set cache_file [file join $icon_cat_dir $cache_base_name]
    } else {
        set cache_file [file join $icon_cat_dir "$cache_base_name.png"]
    }
    
    if {[file exists $cache_file]} {file delete $cache_file}
    
    if {[dict exists $button_to_desktop $name]} {
        dict unset button_to_desktop $name
    }
    if {[dict exists $search_terms $name]} {
        dict unset search_terms $name
    }
    
    destroy $button
    set safe_name [string map {. _ : _ / _ " " _} $name]
    if {[winfo exists $canvas.lbl_$safe_name]} {
        destroy $canvas.lbl_$safe_name
    }
    
    # Обновляем результаты поиска
    set query [$main.search.entry get]
    if {$query ne ""} {
        fuzzy_search $query "Все"
    }
}

# Сборка кэша с автоматическим перезапуском
proc build_cache {} {
    global BUTTON_DIR ICON_CACHE_DIR categories button_to_desktop placeholder_icon config cache_desktop_files cache_built argv0
    
    set progress [toplevel .progress]
    wm title $progress "Инициализация кэша"
    wm attributes $progress -topmost 1
    
    set screen_width [winfo screenwidth .]
    set screen_height [winfo screenheight .]
    set win_width 400
    set win_height 200
    set x [expr {($screen_width - $win_width) / 2}]
    set y [expr {($screen_height - $win_height) / 2}]
    wm geometry $progress ${win_width}x${win_height}+${x}+${y}
    
    set bg_color [dict get $config Layout bg_right]
    set fg_color [dict get $config Layout font_color]
    
    $progress configure -background $bg_color
    
    frame $progress.content -background $bg_color -borderwidth 1 -relief groove
    pack $progress.content -expand true -fill both -padx 10 -pady 10
    
    label $progress.content.label -text "Формирование кэша, пожалуйста, подождите..." \
        -background $bg_color -foreground $fg_color -font "TkDefaultFont 9"
    pack $progress.content.label -pady 5
    
    ttk::progressbar $progress.content.bar -mode determinate -maximum 100 -value 0
    pack $progress.content.bar -fill x -pady 5
    
    update idletasks

    # Сбор и обработка файлов .desktop
    set desktop_files {}
    foreach dir {"/home/live/.local/share/applications" "/usr/share/applications" "/usr/local/share/applications"} {
        if {[file exists $dir]} {
            lappend desktop_files {*}[glob -nocomplain -directory $dir "*.desktop"]
        }
    }
    
    set total_items [llength $desktop_files]
    if {$total_items == 0} {
        destroy $progress
        return
    }

    set update_threshold [expr {max(1, int($total_items / 100))}]
    set processed_items 0

    foreach file $desktop_files {
        set info [parse_desktop_file $file]
        set name [dict get $info name]
        set exec_cmd [dict get $info exec]
        set icon [dict get $info icon]
        
        if {$name ne "" && $exec_cmd ne ""} {
            set cat "Все"
            set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
            set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
            set desktop_filename [file tail $file]
            set dest_file [file join $cat_dir $desktop_filename]
            file copy -force $file $dest_file
            dict set button_to_desktop $name $dest_file

            if {$icon ne ""} {
                set img [find_icon $icon $exec_cmd]
                if {$img ne $placeholder_icon} {
                    # Проверяем, чтобы не было двойного расширения
                    set cache_base_name [string map {/ _} $name]
                    if {[string match "*.png" $cache_base_name]} {
                        set cache_file [file join $icon_cat_dir $cache_base_name]
                    } else {
                        set cache_file [file join $icon_cat_dir "$cache_base_name.png"]
                    }
                    catch {$img write $cache_file -format png}
                }
            }
        }

        incr processed_items
        if {$processed_items % $update_threshold == 0 || $processed_items == $total_items} {
            $progress.content.bar configure -value [expr {($processed_items * 100) / $total_items}]
            update idletasks
        }
    }
    
    # Кэшируем список файлов
    set cat_dir [file join $BUTTON_DIR "Все"]
    dict set cache_desktop_files "Все" [glob -nocomplain -directory $cat_dir "*.desktop"]
    
    destroy $progress
    
    # Устанавливаем флаг, что кэш был создан
    set cache_built 1
    
    # Сохраняем кэш иконок
    save_icon_type_cache
    
    # Автоматический перезапуск программы
    after 500 {
        # Запуск нового экземпляра программы
        if {$::cache_built} {
            exec $::argv0 &
            exit
        }
    }
}

# Инициализация кэша
proc initialize_cache {} {
    global BUTTON_DIR categories cache_desktop_files
    set cache_empty 1
    
    foreach {cat _} $categories {
        set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $cat]]
        set desktop_files [glob -nocomplain -directory $cat_dir "*.desktop"]
        dict set cache_desktop_files $cat $desktop_files
        
        if {[llength $desktop_files] > 0} {
            set cache_empty 0
        }
    }
    
    if {$cache_empty} {
        build_cache
    }
}

#p9

# Глобальные переменные для навигации с клавиатуры
set current_focus "search"  ;# search или icons
set selected_icon_index -1  ;# Индекс выбранной иконки (-1 = не выбрано)
set visible_icons {}        ;# Список отображаемых иконок (имена)

# Добавление кнопки приложения
proc add_app_button {name exec_cmd icon desktop_file canvas x y {is_pinned 0}} {
    global placeholder_icon config search_terms visible_icons
    set scale [dict get $config Layout icon_scale]
    set new_size [expr {int(48 * $scale)}]
    if {$new_size < 48} {set new_size 48}
    set font_size [expr {int(9 * $scale)}]
    if {$font_size < 9} {set font_size 9}
    
    set safe_name [string map {. _ : _ / _ " " _} $name]
    if {[winfo exists $canvas.btn_$safe_name]} {
        destroy $canvas.btn_$safe_name
        destroy $canvas.lbl_$safe_name
    }
    
    set btn [button $canvas.btn_$safe_name -image $placeholder_icon -borderwidth 0 -width $new_size \
             -height $new_size -background [dict get $config Layout bg_right] \
             -highlightbackground [dict get $config Layout button_border_color]]
    set btn_id [$canvas create window $x $y -window $btn -anchor center]
    
    set lbl [label $canvas.lbl_$safe_name -text $name -font "TkDefaultFont $font_size" \
             -wraplength [expr {$new_size + 20}] -justify center \
             -foreground [dict get $config Layout font_color] -background [dict get $config Layout bg_right]]
    set lbl_id [$canvas create window $x [expr {$y + $new_size/2 + 2}] -window $lbl -anchor n]
    
    bind $btn <Enter> [list show_tooltip %W $name %X %Y]
    bind $btn <Leave> {destroy .tooltip}
    bind $btn <ButtonPress-1> [list handle_button_press %W $exec_cmd $name $desktop_file]
    bind $btn <ButtonRelease-1> [list handle_button_release %W $exec_cmd $desktop_file]
    bind $btn <Button-3> [list delete_button %W $name $desktop_file $canvas]
    
    dict set search_terms $name [list $btn_id $lbl_id $exec_cmd $icon $desktop_file]
    
    # Добавляем индикатор закрепления, если иконка закреплена
    if {$is_pinned} {
        $btn configure -relief raised -borderwidth 1 -highlightthickness 1 -highlightcolor "#36B07C" -highlightbackground "#36B07C"
    }
    
    # Добавляем иконку в список видимых иконок для навигации с клавиатуры
    lappend visible_icons $name
    
    return $btn
}

# Асинхронная загрузка иконки с улучшенной обработкой ошибок
proc load_icon_async {btn icon exec_cmd name desktop_file} {
    global ICON_CACHE_DIR placeholder_icon config
    
    # Проверяем, существует ли виджет кнопки
    if {![winfo exists $btn]} {
        return
    }
    
    set cat [lindex [split [file dirname $desktop_file] "/"] end]
    set icon_cat_dir [file join $ICON_CACHE_DIR [string map {" " "_"} $cat]]
    
    # Проверяем, чтобы не было двойного расширения
    set cache_base_name [string map {/ _} $name]
    if {[string match "*.png" $cache_base_name]} {
        set cache_file [file join $icon_cat_dir $cache_base_name]
    } else {
        set cache_file [file join $icon_cat_dir "$cache_base_name.png"]
    }
    
    if {[file exists $cache_file]} {
        if {![catch {
            set img [image create photo -file $cache_file]
            if {[winfo exists $btn]} {
                $btn configure -image $img
            }
        }]} {
            # Обработка выполнена успешно
        }
    } elseif {$icon ne ""} {
        set is_symlink [string match "* (Ссылка)" $name]
        set img [find_icon $icon $exec_cmd $is_symlink]
        if {$img ne $placeholder_icon} {
            if {[winfo exists $btn]} {
                $btn configure -image $img
            }
            if {![catch {$img write $cache_file -format png}]} {
                # Изображение успешно сохранено
            }
        }
    }
}

# Отображение всплывающей подсказки
proc show_tooltip {widget text x y} {
    if {[winfo exists .tooltip]} {destroy .tooltip}
    set tooltip [toplevel .tooltip -background lightyellow -borderwidth 1 -relief solid]
    wm overrideredirect $tooltip 1
    label $tooltip.label -text $text -background lightyellow -font {TkDefaultFont 9}
    pack $tooltip.label -padx 2 -pady 2
    wm geometry $tooltip +[expr {$x + 10}]+[expr {$y + 10}]
}

# Управление панелью результатов
proc show_results_panel {} {
    global main results_visible config
    
    if {$results_visible} {return}
    
    if {![winfo exists $main.results]} {
        frame $main.results -background [dict get $config Layout bg_right]
        canvas $main.results.canvas -xscrollcommand "$main.results.scroll set" -background [dict get $config Layout bg_right]
        scrollbar $main.results.scroll -orient horizontal -command "$main.results.canvas xview"
        pack $main.results.scroll -side bottom -fill x
        pack $main.results.canvas -side top -fill both -expand true
        
        if {$::tcl_platform(platform) eq "windows"} {
            bind $main.results.canvas <MouseWheel> {%W xview scroll [expr {-%D / 120 * 4}] units}
        } else {
            bind $main.results.canvas <Button-4> {%W xview scroll -4 units}
            bind $main.results.canvas <Button-5> {%W xview scroll 4 units}
        }
        
        bind $main.results.canvas <Configure> {
            update_canvas_size %W
            update_selection_after_resize
        }
    }
    
    pack $main.results -fill both -expand true -padx 5 -pady 5
    set results_visible 1
}

proc hide_results_panel {} {
    global main results_visible
    if {!$results_visible} {return}
    if {[winfo exists $main.results]} {pack forget $main.results}
    set results_visible 0
}

# Функция для выделения иконки по индексу
proc highlight_icon {index} {
    global main config visible_icons selected_icon_index
    
    # Проверяем существование канваса
    if {![winfo exists $main.results.canvas]} {
        return
    }
    
    # Сначала сбрасываем визуальное оформление всех кнопок
    foreach name $visible_icons {
        set safe_name [string map {. _ : _ / _ " " _} $name]
        if {[winfo exists $main.results.canvas.btn_$safe_name]} {
            $main.results.canvas.btn_$safe_name configure -relief flat -borderwidth 0 \
                -background [dict get $config Layout bg_right] -highlightthickness 0
            
            # Восстанавливаем оформление закрепленных иконок
            if {[is_pinned $name]} {
                $main.results.canvas.btn_$safe_name configure -relief raised -borderwidth 1 -highlightthickness 1 \
                    -highlightcolor "#36B07C" -highlightbackground "#36B07C"
            }
        }
    }
    
    # Проверяем, что индекс действителен
    if {$index < 0 || $index >= [llength $visible_icons]} {
        set selected_icon_index -1
        return
    }
    
    # Выделяем новую иконку
    set selected_icon_index $index
    set name [lindex $visible_icons $index]
    set safe_name [string map {. _ : _ / _ " " _} $name]
    
    if {[winfo exists $main.results.canvas.btn_$safe_name]} {
        set btn $main.results.canvas.btn_$safe_name
        
        # Делаем кнопку выделенной (синий фон)
        $btn configure -relief sunken -borderwidth 2 -background "#5897AB"
    }
}

# Функция обновления выделения после изменения размера
proc update_selection_after_resize {} {
    global selected_icon_index
    
    if {$selected_icon_index >= 0} {
        # Сохраняем текущий индекс
        set current_index $selected_icon_index
        
        # Снимаем выделение
        highlight_icon -1
        
        # Восстанавливаем выделение с небольшой задержкой
        after 100 [list highlight_icon $current_index]
    }
}

# Функция для перемещения выделения на следующую иконку
proc select_next_icon {} {
    global selected_icon_index visible_icons main config
    
    if {[llength $visible_icons] == 0} {
        return
    }
    
    # Получаем параметры отображения
    set padding [dict get $config Layout button_padding]
    set scale [dict get $config Layout icon_scale]
    set btn_width [expr {int(48 * $scale)}]
    if {$btn_width < 48} {set btn_width 48}
    
    # Рассчитываем новый индекс
    set new_index [expr {$selected_icon_index + 1}]
    if {$new_index >= [llength $visible_icons]} {
        set new_index 0
        # При переходе от последней к первой иконке, сбрасываем скролл в начало
        $main.results.canvas xview moveto 0.0
    } else {
        # Простое правило: если выбрана каждая 3-я иконка, прокручиваем вправо
        if {$new_index % 3 == 0} {
            $main.results.canvas xview scroll 1 units
        }
    }
    
    # Выделяем новую иконку
    highlight_icon $new_index
}

# Функция для перемещения выделения на предыдущую иконку
proc select_prev_icon {} {
    global selected_icon_index visible_icons main config
    
    if {[llength $visible_icons] == 0} {
        return
    }
    
    # Рассчитываем новый индекс
    set new_index [expr {$selected_icon_index - 1}]
    if {$new_index < 0} {
        set new_index [expr {[llength $visible_icons] - 1}]
        
        # При переходе от первой к последней иконке, скроллим в конец
        set scroll_region [$main.results.canvas cget -scrollregion]
        if {$scroll_region ne ""} {
            set total_width [lindex $scroll_region 2]
            set canvas_width [$main.results.canvas cget -width]
            
            # Прокручиваем прямо в конец списка
            $main.results.canvas xview moveto 1.0
            
            # Затем немного назад, чтобы последняя иконка была видна
            $main.results.canvas xview scroll -4 units
        }
    } else {
        # Простое правило: если выбрана каждая 3-я иконка, прокручиваем влево
        if {$new_index % 3 == 0} {
            $main.results.canvas xview scroll -1 units
        }
    }
    
    # Выделяем новую иконку
    highlight_icon $new_index
}

# Функция для активации выбранной иконки
proc activate_selected_icon {} {
    global main selected_icon_index visible_icons search_terms
    
    if {$selected_icon_index < 0 || $selected_icon_index >= [llength $visible_icons]} {
        return
    }
    
    set name [lindex $visible_icons $selected_icon_index]
    if {[dict exists $search_terms $name]} {
        set icon_data [dict get $search_terms $name]
        set exec_cmd [lindex $icon_data 2]
        set desktop_file [lindex $icon_data 4]
        
        set safe_name [string map {. _ : _ / _ " " _} $name]
        set btn $main.results.canvas.btn_$safe_name
        
        # Имитируем нажатие и отпускание кнопки
        handle_button_press $btn $exec_cmd $name $desktop_file
        handle_button_release $btn $exec_cmd $desktop_file
    }
}

# Функция для переключения фокуса между поиском и иконками
proc switch_focus_to_icons {} {
    global current_focus visible_icons
    
    if {$current_focus eq "search" && [llength $visible_icons] > 0} {
        set current_focus "icons"
        highlight_icon 0
    }
}

proc switch_focus_to_search {} {
    global current_focus main selected_icon_index
    
    if {$current_focus eq "icons"} {
        set current_focus "search"
        highlight_icon -1  ;# Снимаем выделение с иконок
        focus $main.search.entry
    }
}

# Новая функция для отображения иконок
proc display_icons {mode {query ""} {category "Все"}} {
    global BUTTON_DIR main search_terms config cache_desktop_files cache_app_info pinned_icons visible_icons selected_icon_index
    if {![info exists main]} {return}
    
    # Сбрасываем список видимых иконок и выделение
    set visible_icons {}
    set selected_icon_index -1
    
    # Показываем панель результатов (это создаст канвас, если его еще нет)
    show_results_panel
    
    # Удаляем все с канваса
    if {[winfo exists $main.results.canvas]} {
        $main.results.canvas delete all
    }
    
    set search_terms [dict create]
    
    # Получаем параметры отображения
    set padding [dict get $config Layout button_padding]
    set scale [dict get $config Layout icon_scale]
    set btn_width [expr {int(48 * $scale)}]
    if {$btn_width < 48} {set btn_width 48}
    set btn_height [expr {int(48 * $scale)}]
    if {$btn_height < 48} {set btn_height 48}
    
    # Список иконок для отображения
    set icon_list {}
    
    # В зависимости от режима собираем нужные иконки
    if {$mode eq "pinned_only"} {
        # Только закрепленные иконки
        dict for {name data} $pinned_icons {
            lassign $data exec_cmd desktop_file
            set info [parse_desktop_file $desktop_file]
            set icon [dict get $info icon]
            lappend icon_list [list $name $exec_cmd $icon $desktop_file 1]
        }
        
        # Если нет закрепленных иконок и нет поискового запроса, скрываем панель
        if {[llength $icon_list] == 0 && $query eq ""} {
            hide_results_panel
            return
        }
    } elseif {$mode eq "search"} {
        # Поиск приложений
        set cat_dir [file join $BUTTON_DIR [string map {" " "_"} $category]]
        if {![file exists $cat_dir]} {
            # Если директория категории не существует, показываем только закрепленные
            return [display_icons "pinned_only"]
        }
        
        # Кэшируем список файлов .desktop
        if {![dict exists $cache_desktop_files $category]} {
            set desktop_files [glob -nocomplain -directory $cat_dir "*.desktop"]
            dict set cache_desktop_files $category $desktop_files
        } else {
            set desktop_files [dict get $cache_desktop_files $category]
        }
        
        if {[llength $desktop_files] == 0} {
            # Если нет файлов .desktop, показываем только закрепленные
            return [display_icons "pinned_only"]
        }
        
        set query_lower [string tolower $query]
        
        # Сначала добавляем закрепленные иконки, соответствующие поиску
        dict for {name data} $pinned_icons {
            if {[string match "*$query_lower*" [string tolower $name]]} {
                lassign $data exec_cmd desktop_file
                set info [parse_desktop_file $desktop_file]
                set icon [dict get $info icon]
                lappend icon_list [list $name $exec_cmd $icon $desktop_file 1]
            }
        }
        
        # Затем добавляем найденные незакрепленные иконки
        foreach desktop_file $desktop_files {
            set info [parse_desktop_file $desktop_file]
            set app_name [dict get $info name]
            set exec_cmd [dict get $info exec]
            set icon [dict get $info icon]
            
            if {$app_name eq "" || $exec_cmd eq ""} {continue}
            
            if {[string match "*$query_lower*" [string tolower $app_name]] && ![is_pinned $app_name]} {
                lappend icon_list [list $app_name $exec_cmd $icon $desktop_file 0]
            }
        }
        
        # Если ничего не найдено и нет закрепленных иконок, скрываем панель
        if {[llength $icon_list] == 0} {
            hide_results_panel
            return
        }
    }
    
    # Отображаем иконки
    set total_buttons [llength $icon_list]
    
    update idletasks
    set win_height [winfo height $main.results.canvas]
    if {$win_height <= 1} {set win_height 150}
    
    # Располагаем в горизонтальную ленту
    set row_height [expr {$btn_height + 25}]
    set canvas_height $row_height
    set canvas_width [expr {$total_buttons * ($btn_width + $padding) + $padding}]
    
    $main.results.canvas configure -scrollregion "0 0 $canvas_width $canvas_height"
    $main.results.canvas configure -height $canvas_height
    
    for {set i 0} {$i < $total_buttons} {incr i} {
        lassign [lindex $icon_list $i] app_name exec_cmd icon desktop_file is_pinned
        set x [expr {$i * ($btn_width + $padding) + $padding + $btn_width/2}]
        set y [expr {$canvas_height / 2 - 10}]
        
        set btn [add_app_button $app_name $exec_cmd $icon $desktop_file $main.results.canvas $x $y $is_pinned]
        after idle [list load_icon_async $btn $icon $exec_cmd $app_name $desktop_file]
    }
    
    # Сбрасываем скролл в начало
    $main.results.canvas xview moveto 0.0
}

# Модифицированная функция поиска
proc fuzzy_search {query category} {
    global main
    if {![info exists main]} {return}
    
    if {$query eq ""} {
        # Если поиск пустой, показываем только закрепленные иконки
        display_icons "pinned_only"
        return
    }
    
    # Иначе выполняем поиск
    display_icons "search" $query $category
}

# Обновление размера канваса
proc update_canvas_size {w} {
    global main
    if {![info exists main]} {return}
    set query [$main.search.entry get]
    if {$query ne ""} {
        fuzzy_search $query "Все"
    } else {
        display_icons "pinned_only"
    }
}

# Очистка поиска
proc clear_search {} {
    global main
    $main.search.entry delete 0 end
    display_icons "pinned_only"
}

# Кэширование терминала
proc cache_terminal_cmd {} {
    global cached_terminal_cmd
    if {$cached_terminal_cmd ne ""} {return}
    foreach term {xterm uxterm lxterminal xfce4-terminal gnome-terminal terminator konsole} {
        if {[auto_execok $term] ne ""} {
            set cached_terminal_cmd $term
            break
        }
    }
}

#p10

# Обработка запуска с параметром --update-cache
if {[lindex $argv 0] eq "--update-cache"} {
    create_directories
    build_cache
    save_icon_type_cache
    exit
}

# Загрузка и инициализация
load_config
load_icon_type_cache
create_directories
create_placeholder_icon
initialize_cache
cache_terminal_cmd
load_pinned_icons

# Создание основного окна
set main [toplevel .main]
wm title $main "Arcturus"

# Установка размера и положения
set screen_width [winfo screenwidth .]
set screen_height [winfo screenheight .]
set win_width [expr {int($screen_width * 0.6)}]
set win_height 180
set x [expr {int(($screen_width - $win_width) / 2)}]
set y [expr {int(($screen_height - $win_height) / 2)}]
wm geometry $main ${win_width}x${win_height}+${x}+${y}

# Создание строки поиска
frame $main.search -pady 5
pack $main.search -side top -fill x -padx 5

frame $main.search.entry_frame -borderwidth 1 -relief groove -background [dict get $config Layout selection_color]
pack $main.search.entry_frame -side top -fill x
entry $main.search.entry -width 30 -borderwidth [dict get $config Layout search_entry_border_width] \
      -relief flat -background white -font "TkDefaultFont 12"
pack $main.search.entry -side left -in $main.search.entry_frame -fill x -expand true -pady 2 -padx 2

# Добавляем кнопку настроек
button $main.search.settings -text "⚙" -font "TkDefaultFont 12 bold" \
       -relief flat -borderwidth 1 -background [dict get $config Layout bg_right] \
       -foreground [dict get $config Layout font_color] -command open_settings_window
pack $main.search.settings -side right -in $main.search.entry_frame -padx 2 -pady 2

# Показываем закрепленные иконки в панели результатов
display_icons "pinned_only"

# Обработка событий
bind $main.search.entry <KeyRelease> {
    # Не обрабатываем клавиши навигации в KeyRelease
    if {"%K" ni {"Down" "Up" "Left" "Right" "Return" "Escape"}} {
        global search_timer
        if {[info exists search_timer] && $search_timer ne ""} {
            after cancel $search_timer
        }
        set search_timer [after 150 {
            set query [$::main.search.entry get]
            fuzzy_search $query "Все"
            set ::search_timer ""
        }]
    }
}

# Добавляем специальную обработку клавиш навигации для поля ввода
bind $main.search.entry <Down> {
    switch_focus_to_icons
    break
}

# Добавляем глобальную обработку клавиш для всего окна
bind $main <KeyPress-Down> {
    if {$::current_focus eq "search"} {
        switch_focus_to_icons
    }
}

bind $main <KeyPress-Up> {
    if {$::current_focus eq "icons"} {
        switch_focus_to_search
    }
}

bind $main <KeyPress-Left> {
    if {$::current_focus eq "icons"} {
        select_prev_icon
    }
}

bind $main <KeyPress-Right> {
    if {$::current_focus eq "icons"} {
        select_next_icon
    }
}

bind $main <KeyPress-Return> {
    if {$::current_focus eq "icons"} {
        activate_selected_icon
    }
}

bind $main <KeyPress-Escape> {
    if {$::current_focus eq "icons"} {
        switch_focus_to_search
    } else {
        # Если фокус в поиске и поле не пустое, очищаем поле
        if {[$::main.search.entry get] ne ""} {
            clear_search
        } else {
            # Если поле поиска пустое, закрываем программу
            save_icon_type_cache
            save_pinned_icons
            exit
        }
    }
}

# Обработка закрытия окна
wm protocol $main WM_DELETE_WINDOW {save_icon_type_cache; save_pinned_icons; exit}

# Устанавливаем фокус в строку поиска
focus $main.search.entry

# Применяем цвета и масштаб
update idletasks
apply_scale
apply_colors
apply_font_settings

# Добавляем информацию о версии и пользователе с текущей датой и временем
set version_info "Версия 1.2.5 от 2025-09-03 07:44:52. Пользователь: totiks2012"

# Запускаем фоновую загрузку кэша
after 1000 {
    foreach {cat _} $::categories {
        set cat_dir [file join $::BUTTON_DIR [string map {" " "_"} $cat]]
        if {[dict exists $::cache_desktop_files $cat]} {
            set desktop_files [dict get $::cache_desktop_files $cat]
            foreach desktop_file $desktop_files {
                if {![dict exists $::cache_app_info $desktop_file]} {
                    set info [parse_desktop_file $desktop_file]
                    dict set ::cache_app_info $desktop_file $info
                }
            }
        }
    }
}

tkwait window $main

#p11

