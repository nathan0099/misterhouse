use strict;

use vars qw(%Menus);

#---------------------------------------------------------------------------
#  menu_parse will parse the menu into %Menus
#---------------------------------------------------------------------------

sub menu_parse {
    my ($template, $menu_group) = @_;
    $menu_group = 'default' unless $menu_group;

    my (%menus, $menu, $index, %voice_cmd_list);
    $Menus{$menu_group} = \%menus;

                                # Find all the valid Voice_Cmd text
    for my $object (map {&get_object_by_name($_)} &list_objects_by_type('Voice_Cmd')) {
                                # Pick first of {a,b} enumerations (e.g. {tell me,what is} )
        my $text = $$object{text};
        $text =~ s/\{([^,]+).+?\}/$1/g;
        $voice_cmd_list{$text} = $object;
    }


    my $menu_states_cnt = 'states0';
    for (split /\n/, $template) {
        my ($type, $data) = $_ =~ /^\s*(\S+)\:\s*(.+?)\s*$/;
        next if /^\s*\#/;       # Ignore comments
        $data =~ s/\s+\#.+//;   # Ignore comments

                                # Pull out 'start menu' records:  M: Lights 
        if ($type eq 'M') {
            $menu = $data;
            $index = -1;
            if ($menus{$menu}) {
                print "\nWarning, duplicate menu: $menu\n\n";
            }
            else {
                push @{$menus{menu_list}}, $menu;
            }
        }
        elsif ($type) {
                                # Allow for menu level parms like P: if speced before any items
            if ($type ne 'D' and $index == -1) {
                $menus{$menu}{"default:$type"} = $data;
            }
                                # Pull out 'select,action,response' records:  A: Left bedroom light $state
            else {
                $index++ if $type eq 'D';
                $menus{$menu}{items}[$index]{$type} = $data;
            }
#           print "db m=$menu i=$index type=$type d=$data.\n";
        }
        else {
            print "Menu parsing error: $_\n" unless /^\s*$/;
        }
                                # States can be found in item text and Action/Response records
        my ($prefix, $states, $suffix) = $data =~ /(.*)\[(.+)\](.*)/;

        if ($states) {
            $menus{$menu}{items}  [$index]{$type . 'prefix'}  = $prefix;
            $menus{$menu}{items}  [$index]{$type . 'suffix'}  = $suffix;
            @{$menus{$menu}{items}[$index]{$type . 'states'}} = split ',', $states;


                                # Create a states menu for each unique set of states
            if ($type eq 'D') {
                unless ($menus{menu_list_states}{$states}) {
                    $menus{menu_list_states}{$states} = ++$menu_states_cnt;
                    $menus{$menu_states_cnt}{states}  = $states;
                    push @{$menus{menu_list}}, $menu_states_cnt;
                    my $i = 0;
                    for my $state (split ',', $states) {
                        $menus{$menu_states_cnt}{items}[$i]{D}    = $state;
                        $menus{$menu_states_cnt}{items}[$i]{A}    = 'state_select';
                        $menus{$menu_states_cnt}{items}[$i]{goto} = 'prev';
                        $i++;
                    }
                }
                $menus{$menu}{items}[$index]{'Dstates_menu'} = $menu_states_cnt;
            }
        }            
    }
                                # Setup actions and goto for each state
    my %unused_menus = %menus;
    for $menu (@{$menus{menu_list}}) {
        for my $ptr (@{$menus{$menu}{items}}) {

                                # Default action = display if no action and the display matches a voice command
            if (!$$ptr{A} and $voice_cmd_list{$$ptr{D}}) {
                $$ptr{A} = $$ptr{D};
                @{$$ptr{Astates}} = @{$$ptr{Dstates}} if $$ptr{Dstates};
                $$ptr{Aprefix} = $$ptr{Dprefix};
                $$ptr{Asuffix} = $$ptr{Dsuffix};
            }

                                # Allow for: turn fan [on,off]
            my $i = 0;
            if ($$ptr{Astates}) {
                for my $state (@{$$ptr{Astates}}) {
                    $$ptr{actions}[$i++] = "$$ptr{Aprefix}'$state'$$ptr{Asuffix}";
                }
            }
                                # Allow for: set $object $state
            elsif ($$ptr{Dstates}) {
                for my $state (@{$$ptr{Dstates}}) {
                    my $action = $$ptr{A};
                    $action =~ s/\$state/'$state'/;
                    $$ptr{actions}[$i++] = $action;
                }
            }

                                # Now verify that all menus exist and are used
                                # Also set default goto if needed

                                # Explicit goto menu is given
            if ($$ptr{goto} and $menus{$$ptr{goto}}) {
                delete $unused_menus{$$ptr{goto}};
            }
                                # The display text matches a submenu
            elsif ($menus{$$ptr{D}}) {
                $$ptr{goto} = $$ptr{D};
                delete $unused_menus{$$ptr{goto}};
            }
                                # For an action, stay on the goto menu by default
            elsif ($$ptr{A}) {
                $$ptr{goto} = $menu;
                delete $unused_menus{$$ptr{goto}};
            }
                                # For a response only, stay on the goto menu by default
            elsif ($$ptr{R}) {
                $$ptr{goto} = $menu;
                delete $unused_menus{$$ptr{goto}};
            }
            else {
                print "\nWarning, goto menu not found: menu=$menu goto=$$ptr{goto} text=$$ptr{D}\n\n" unless
                    $$ptr{goto} eq 'prev';
            }
        }
    }

    delete $unused_menus{menu_list_states};
    delete $unused_menus{menu_list};
    delete $unused_menus{$menus{menu_list}[0]};
    for (sort keys %unused_menus) {print "\nWarning, these menus were unused: $_\n\n" unless /^states\d+$/};

                                # Do a depth first level count
    my @menus_list = &menu_submenus($menu_group, $menus{menu_list}[0], 99, 1);
    my $level = 0;
    for my $ptr (@menus_list) {
        for my $menu (@{$ptr}) {
            $menus{$menu}{level} = $level unless defined $menus{$menu}{level};
        }
        $level++;
    }
                                # Create a sorted menu list
    @{$menus{menu_list_sorted}} = sort {$menus{$a}{level} <=> $menus{$b}{level}} @{$menus{menu_list}};

}

                                # Find just one level of submenus
sub menu_submenu {
    my ($menu_group, $menu) = @_;
    my (@menus, %menus_seen);
    for my $ptr (@{$Menus{$menu_group}{$menu}{items}}) {
        my $menu_sub;
        if ($$ptr{A}) {
            $menu_sub = $$ptr{Dstates_menu} if $$ptr{Dstates_menu};
        }
        else {
            $menu_sub = $$ptr{goto}
        }
        next unless $menu_sub;
        unless ($menus_seen{$menu_sub}++) {
            push @menus, $menu_sub;
                                # Track just the first parent ?
            $Menus{$menu_group}{$menu_sub}{parent} = $menu unless $menu eq $menu_sub;
        }
    }
    return @menus;
}

                                # Find nn levels of submenus, grouped by levels
sub menu_submenus {
    my ($menu_group, $menu, $levels, $levelized) = @_;
    my (@menus_list, %menus_seen);
    my @menus_left = ($menu);
    while (@menus_left) {
        push @menus_list, [@menus_left];
        my @menus_next;
        for my $menu (@menus_left) {
            push @menus_next, &menu_submenu($menu_group, $menu) unless $menus_seen{$menu}++;
        }
        @menus_left = @menus_next;
    }
    if ($levelized) {
        return @menus_list;
    }
                                # Return all menus for all levels in one list
    else {
        my (@menus_total, %menus_seen);
        for my $ptr (@menus_list) {
#           print "db1 m=@{$ptr}\n";
            for my $menu (@{$ptr}) {
                push @menus_total, $menu unless $menus_seen{$menu}++;
            };
        }
        return @menus_total;
    }
}


#---------------------------------------------------------------------------
#  menu_create will create a menu for all voice commands
#---------------------------------------------------------------------------

sub menu_create {
    my ($file) = @_;
    my $menu_top = "# This is an auto-generated file.  Rename it before you edit it, then update menu.pl to point to it\nM: mh\n";
    my $menu;
    for my $category (sort &list_code_webnames('Voice_Cmd')) {
        $menu_top .= "  D: $category\n";
        $menu     .= "M: $category\n";
        for my $object_name (sort &list_objects_by_webname($category)) {
            my $object = &get_object_by_name($object_name);
            next unless $object and $object->isa('Voice_Cmd');
            my $authority = $object->get_authority;
#           next unless $authority =~ /anyone/ or 
#                       $config_parms{tellme_pin} and $Cookies{vxml_cookie} eq $config_parms{tellme_pin};

                                # Pick first of {a,b} enumerations (e.g. {tell me,what is} )
            my $text = $$object{text};
            $text =~ s/\{([^,]+).+?\}/$1/g;

            $menu .= sprintf "  D: %-50s  # %-25s %10s\n", $text, $object_name, $authority;
        }
    }
    &file_write($file, $menu_top . $menu);
    return $menu_top . $menu;
}    

#---------------------------------------------------------------------------
#  menu_run will be called to execute menu actions
#     $format:  v->vxml,  h->html,  w->wml,  l->lcd
#---------------------------------------------------------------------------

sub menu_run {
    my ($menu_group, $menu, $item, $state, $format) = split ',', $_[0] if $_[0];

    my ($action, $cmd);
    my $ptr = $Menus{$menu_group}{$menu}{items}[$item];
    if (defined $state and $$ptr{actions}) {
        $action = $$ptr{actions}[$state];
    }
    else {
        $action = $$ptr{A};
    }
    my $authority = $$ptr{P};
    my $display   = $$ptr{D};
    my $response  = $$ptr{R};
    $response  = $Menus{$menu_group}{$menu}{'default:R'} unless $response;

    $action    = '' unless defined $action; # Avoid uninit warnings
    $state     = '' unless defined $state;
    $format    = '' unless defined $format;
    $authority = '' unless defined $authority;
    $display   = '' unless defined $display; 
    $response  = '' unless defined $response;

    $Menus{menu_data}{response_format} = $format;

                                # Allow anyone to run set_authority('anyone') commands
    my $ref;
    if ($cmd = $action) {
        $cmd =~ s/\'//g;        # Drop the '' quotes around state if a voice cmd
        ($ref) = &Voice_Cmd::voice_item_by_text(lc($cmd));
    }
    $authority = $ref->get_authority           unless $authority or !$ref;
    $authority = $Password_Allow{$display}     unless $authority;
    $authority = $Password_Allow{$cmd}         unless $authority;
    $authority = $Menus{$menu_group}{$menu}{'default:P'} unless $authority;
    $authority = '' unless $authority;

    $Socket_Ports{http}{client_ip_address} = '' unless $Socket_Ports{http}{client_ip_address};
    my $msg = "menu_run: a=$Authorized,$authority f=$format ip=$Socket_Ports{http}{client_ip_address} mg=$menu_group m=$menu i=$item s=$state a=$action r=$response";
    print "$msg\n";
    logit "$config_parms{data_dir}/logs/menu_run.log", $msg;

    unless ($Authorized or $authority or $format eq 'l') {
        if ($format eq 'v') {
            my $vxml = qq|<form><block><audio>Sorry, authorization required to run $action</audio><goto next='_lastanchor'/></block></form>|;
            return &vxml_page($vxml);
        }
                                # If wap cell phone id is not in the list, prompt for the password
        elsif ($format eq 'w') {
            unless ($Http{'x-up-subno'} and grep $Http{'x-up-subno'} eq $_, split(/[, ]/, $config_parms{password_allow_phones})) {
                return &html_password('browser'); # wml requires browser login ... no form/cookies for now
            }
        }
        else {
            return &html_password(''); # Html can take cookies or browser ... default to mh.ini password_menu
        }
    }

    if ($action) {
        my $msg = "menu_run: g=$menu_group m=$menu i=$item s=$state => action: $action";
        print_log  $msg;
        print     "$msg\n";
        unless (&run_voice_cmd($cmd)) {
#           package main;   # Need this if we had this code in a package
            eval $action;
            print "Error in menu_run: m=$menu i=$item s=$state action=$action error=$@\n" if $@;
        }
    }

    $Menus{menu_data}{last_response_menu}       = $menu;
    $Menus{menu_data}{last_response_menu_group} = $menu_group;

    if ($response and lc $response eq 'none' and $format eq 'l') {
        return;
    }

                                # Substitute $state
    if (length($state) > 0 and $state >= 0) {
        my $t_state;
        $t_state  = $$ptr{Dstates}[$state] if $$ptr{Dstates};
        $t_state  = $$ptr{Astates}[$state] if $$ptr{Astates};
        if (defined $t_state) {
            $state = $t_state;
        }
        $response = "Set to $state" unless $response;
    }


    if ($response and $response =~ /^eval (.+)/) {
        print "Running eval on: $1\n";
        $response = eval $1;
    }
    elsif ($response) {
        eval "\$response = qq[$response]"; # Allow for var substitution of $state
    }

    if (!$response or $response eq 'last_response') {
        if ($format eq 'l') {
            $Menus{menu_data}{last_response_loop} = $Loop_Count + 3;
            return;
        }
                                # Everything else comes via http_server
        else {
            return "menu_run_response('last_response','$format')"
        }
    }

    return &menu_run_response($response, $format);
}

sub menu_run_response {
    my ($response, $format) = @_;
    ($response, $format) = split ',', $response unless $format; # only 1 arg if called via http last response
    $response = &last_response if $response and $response eq 'last_response';
    $response = 'all done' unless $response;
    if ($format and $format eq 'w') {
        $response =~ s/& /&amp; /g; 
        my $wml = qq|<head><meta forua="true" http-equiv="Cache-Control" content="max-age=0"/></head>\n|;
        $wml   .= qq|<template><do type="accept" label="Prev."><prev/></do></template>\n|;
        $wml   .= qq|<card><p>$response</p></card>|;
        return &wml_page($wml);
    }
    elsif ($format and $format eq 'v') {
#       my $http_root = "http://$config_parms{http_server}:$config_parms{http_port}";
        my $http_root = '';     # Full url is no longer required :)
        my $goto      = "${http_root}sub?menu_vxml($Menus{menu_data}{last_response_menu_group})#$Menus{menu_data}{last_response_menu}";
        print "db1 gt=$goto\n";
        my $vxml = qq|<form><block><audio>$response</audio><goto next='$goto'/></block></form>|;
#       my $vxml = qq|<form><block><audio>$response</audio><goto expr="'$goto'"/></block></form>|;
        return &vxml_page($vxml);
    }
    elsif ($format and $format eq 'h') {
        return &html_page('', $response);
    }
    else {
        return $response;
    }
}

#---------------------------------------------------------------------------
#  menu_html creates the web browser menu interface
#---------------------------------------------------------------------------

sub menu_html {
    my ($menu_group, $menu) = split ',', $_[0] if $_[0];
    $menu_group = 'default' unless $menu_group;
    $menu       = $Menus{$menu_group}{menu_list}[0] unless $menu;

    my @k = keys %main::Menus;

    my $html = "<h1>";
    my $item = 0;
    my $ptr = $Menus{$menu_group};
    for my $ptr2 (@{$$ptr{$menu}{items}}) {
        my $goto = $$ptr2{goto};
                                # Action item
        if ($$ptr2{A}) {
                                # Multiple states
            if ($$ptr2{Dstates}) {
                $html .= "    <li> $$ptr2{Dprefix}\n";
                my $state = 0;
                for my $state_name (@{$$ptr2{Dstates}}) {
                    $html .= "      <a href='/sub?menu_run($menu_group,$menu,$item,$state,h)'>$state_name</a>, \n";
                    $state++;
                }
                $html .= "    $$ptr2{Dsuffix}\n";
            }
                                # One state
            else {
                $html .= "    <li><a href='/sub?menu_run($menu_group,$menu,$item,,h)'>$$ptr2{D}</a>\n";
            }
        }
        elsif ($$ptr2{R}) {
            $html .= "    <li><a href='/sub?menu_run($menu_group,$menu,$item,,h)'>$$ptr2{D}</a>\n";
        }

                                # Menu item
        else {
            $html .= "    <li><a href='/sub?menu_html($menu_group,$goto)'>$goto</a>\n";
        }
        $item++;
    }
    return &html_page($menu, $html);
}

#---------------------------------------------------------------------------
#  menu_wml creates the wml (for WAP enabled cell phones) menu interface
#  You can test it here:  http://www.gelon.net
#  Others listed here: http://www.palowireless.com/wap/browsers.asp
#---------------------------------------------------------------------------

sub menu_wml {
    my ($menu_group, $menu_start) = split ',', $_[0] if $_[0];
    $menu_group = 'default' unless $menu_group;
    $menu_start = $Menus{$menu_group}{menu_list}[0] unless $menu_start;
    logit "$config_parms{data_dir}/logs/menu_wml.log", 
          "ip=$Socket_Ports{http}{client_ip_address} mg=$menu_group m=$menu_start";

    my (@menus, @cards);

                                # Get a list of all menus, by level
    @menus = &menu_submenus($menu_group, $menu_start, 99);
                                # Now build all the cards
    @cards = &menu_wml_cards($menu_group, @menus);

                                # See how many cards will fit in a 1400 character deck.
    my ($i, $length);
    $i = $length = 0;
    while ($i <= $#cards and $length < 1400) {
        $length += length $cards[$i++];
    }
    $i -= 2;                    # The template card is extra

#   print "db2 mcnt=$#menus ccnt=$#cards i=$i l=$length m=@menus, c=@cards.\n";

                                # This time build only for the requested cards that fit
    @cards = &menu_wml_cards($menu_group, @menus[0..$i]);

    return &wml_page("@cards");

}

sub menu_wml_cards {
    my ($menu_group, @menus) = @_;
    my (%menus, @cards);

    %menus = map {$_, 1} @menus;

                                # Dang, can not get a prev button when using select??
    my $template = qq|<template><do type="prev" label="Prev1"><prev/></do></template>\n|;
#                            qq|<do type="accept" label="Prev2"><prev/></do></template>\n|;
    push @cards, $template;

    for my $menu (@menus) {
        my $wml = "\n <card id='$menu'>\n";
                                # Save the menu name in a var (unless it is a states menu)
        unless ($menu =~ /^states\d+$/) {
            $wml .= "  <onevent type='onenterforward'><refresh>\n";
            $wml .= "    <setvar name='prev_menu' value='$menu'/>\n";
            $wml .= "  </refresh></onevent>\n";
        }
        $wml .= "  <p>$menu\n  <select name='prev_value'>\n";
# ivalue=0 does not seem to change anything
#                              <select name='prev_value' ivalue='0'>
# Not sure what select grouping does
#   <optgroup title='test1'>
#   </optgroup>


        my $item = 0;
        for my $ptr (@{$Menus{$menu_group}{$menu}{items}}) {
                                # Action item
            if ($$ptr{A}) {
                                # Multiple states -> goto a state menu
                if ($$ptr{Dstates}) {
                    my $goto = $$ptr{'Dstates_menu'};
                    $goto = ($menus{$goto}) ? "#$goto" : "/sub?menu_wml($menu_group,$goto)";
                    $wml .= "    <option value='$item' onpick='$goto'>$$ptr{Dprefix}..$$ptr{Dsuffix}</option>\n";
                }
                                # States menu
                elsif ($$ptr{A} eq 'state_select') {
                    $wml .= "    <option onpick='/sub?menu_run($menu_group,\$prev_menu,\$prev_value,$item,w)'>$$ptr{D}</option>\n";
                }
                                # One state
                elsif ($$ptr{A} eq 'set_password') {
                    $wml .= "    <option onpick='/SET_PASSWORD'>Set Password</option>\n";
                }
                else {
                    $wml .= "    <option onpick='/sub?menu_run($menu_group,$menu,$item,,w)'>$$ptr{D}</option>\n";
                }
            }
            elsif ($$ptr{R}) {
                $wml .= "    <option onpick='/sub?menu_run($menu_group,$menu,$item,,w)'>$$ptr{D}</option>\n";
            }
                                # Menu item
            else {
                my $goto = $$ptr{goto};
                $goto = ($menus{$goto}) ? "#$goto" : "/sub?menu_wml($menu_group,$goto)";
                $wml .= "    <option onpick='$goto'>$$ptr{D}</option>\n";
            }
            $item++;
        }
        $wml .= "   </select></p>\n </card>\n";
        push @cards, $wml;
    }
    return @cards;
}


#---------------------------------------------------------------------------
#  menu_vxml creates the vxml (for WAP enabled cell phones) menu interface
#---------------------------------------------------------------------------

sub menu_vxml {
    my ($menu_group, $menu_start) = split ',', $_[0] if $_[0];
    $menu_group = 'default'                         unless $menu_group;
    $menu_start = $Menus{$menu_group}{menu_list}[0] unless $menu_start;
    logit "$config_parms{data_dir}/logs/menu_vxml.log",
          "ip=$Socket_Ports{http}{client_ip_address} mg=$menu_group m=$menu_start";

                                # Get a list of all menus, then build vxml forms
    my @menus     = &menu_submenus  ($menu_group, $menu_start, 99);
    my @forms     = &menu_vxml_forms($menu_group, @menus);
    my $greeting  = &vxml_audio('greeting', 'Welcome to Mister House', '/misc/tellme_welcome.wav', "#$menu_start");
    my $vxml_vars = "<var name='prev_menu'/>\n<var name='prev_item'/>\n";
    return &vxml_page($vxml_vars . $greeting . "@forms");
}

sub menu_vxml_forms {
    my ($menu_group, @menus) = @_;
    my (%menus, @forms);
#   my $http_root =  "http://$config_parms{http_server}:$config_parms{http_port}/";
    my $http_root = '';         # Full url is no longer required :)

    for my $menu (@menus) {

        my ($menu_parent, $prompt);
        if ($menu =~ /^states/) {
            $prompt = "Speak $Menus{$menu_group}{$menu}{states}";
            $prompt =~ tr/,/ /;
        }
        else {
            $prompt = "Speak a $menu command";
            $menu_parent = $Menus{$menu_group}{$menu}{parent};
        }

        my (@grammar, @action, @goto);
        my $item = 0;
        for my $ptr (@{$Menus{$menu_group}{$menu}{items}}) {
            my ($grammar, $action, $goto);
            $grammar = $$ptr{D};
                                # Action item
            if ($$ptr{A}) {
                                # Multiple states
                if ($$ptr{Dstates}) {
                    $grammar = "$$ptr{Dprefix} $$ptr{Dsuffix}";
                    $goto    = "#$$ptr{Dstates_menu}";
                    $action .= qq|<assign name="prev_menu"  expr="'$menu'"/>\n|;
                    $action .= qq|<assign name="prev_item"  expr="'$item'"/>\n|;
                }
                                # States menu
                elsif ($$ptr{A} eq 'state_select') {
#                   $goto = "${http_root}sub?menu_run($menu_group,{prev_menu},{prev_item},$item,v)";
# db1x
                    $goto = "${http_root}sub?menu_run($menu_group,' + prev_menu + ',' + prev_item + ',$item,v)";
                }
                                # One state
                else {
                    $goto = "${http_root}sub?menu_run($menu_group,$menu,$item,,v)";
                }
            }
            elsif ($$ptr{R}) {
                $goto = "${http_root}sub?menu_run($menu_group,$menu,$item,,v)";
            }
                                # Menu item
            else {
                $goto = "#$$ptr{goto}";
            }
            push @grammar, $grammar;
            push @action,  $action;
            push @goto,    $goto;
            $item++;
        }
        push @forms, &vxml_form(prompt => $prompt, name => $menu, prev => $menu_parent,
                                grammar => \@grammar, action => \@action, goto => \@goto);
    }
    return @forms;
}


#---------------------------------------------------------------------------
#  menu_lcd* populate the LCD objects
#---------------------------------------------------------------------------
                                # This loads in a menu and refreshes the LCD display data
sub menu_lcd_load {
    my ($lcd, $menu) = @_;
    $menu = $$lcd{menu_name}                        unless $menu;
    $menu = $Menus{$$lcd{menu_group}}{menu_list}[0] unless $menu;
    return unless $menu;

                                # Reset menu only if it is a new one (keep old cursor and state)
    unless ($$lcd{menu_name} and $$lcd{menu_name} eq $menu) {
        my $ptr = $Menus{$$lcd{menu_group}}{$menu};
        my $i = -1;
        for my $ptr2 (@{$$ptr{items}}) {
            $$lcd{menu}[++$i] = $$ptr2{D};
        }
                                # Set initial cursor and display location to 0,0 if a new menu
        $$lcd{cx} = $$lcd{cy} = $$lcd{dy} = 0;
        $$lcd{menu_cnt}  = $i;
        $$lcd{menu_state}     = -1;
        $$lcd{menu_ptr}  = $ptr;
        $$lcd{menu_name} = $menu;
    }
    &menu_lcd_refresh($lcd);    # Refresh the display data
}

                                # This will refresh the LCD Display records
                                # And position the cursor scroll line if needed
sub menu_lcd_refresh {
    my ($lcd) = @_;
    for my $i (0 .. $$lcd{dy_max}) {

        my $row  = $$lcd{dy} + $i;
                                # Use a blank if there is no menu entry for this row
        my $data = ($row <= $$lcd{menu_cnt}) ? $$lcd{menu}[$row] : ' ';
        my $l = length $data;

                                # Do extra stuff on cursor line
        if ($row == $$lcd{cy}) {

                                # Set cursor marker
            $$lcd{cx} = $l if $$lcd{cx} > $l;
            substr($data, $$lcd{cx}, 1) = '#';

                                # If the line does not fit, center the text on the cursor
            my $x = 0;
            if ($l > $$lcd{dx_max}) {
                $x = $$lcd{cx} - $$lcd{dx_max}/2;
                if ($x > 1) {
                    $data = '<' . substr $data, $x;
                }
                else {
                    $x = 0;
                }
            }
        }
        substr($data, $$lcd{dx_max}, 1) = '>' if length($data) > $$lcd{dx_max};
        $$lcd{display}[$i] = $data;
    }
    $$lcd{refresh} = 1;
}

                                # Monitor keypad data (allow for computer keyboard simulation)
sub menu_lcd_navigate {
    my ($lcd, $key) = @_;
    $key = $$lcd{keymap}->{$key} if $$lcd{keymap}->{$key};

    my $menu = $$lcd{menu_name};
    my $ptr  = $$lcd{menu_ptr}{items}[$$lcd{cy}] unless $menu eq 'response';
    
                                # See if we need to scroll the display window
    if ($key eq 'up') {
        $$lcd{cy}-- unless $$lcd{cy} == 0;
        if ($$lcd{cy} < $$lcd{dy}) {
            $$lcd{dy} = $$lcd{cy};
        }
        &menu_lcd_curser_state($lcd, $$lcd{menu_ptr}{items}[$$lcd{cy}]); # Move cursor to the same state
    }
    elsif ($key eq 'down') {
        $$lcd{cy}++ unless $$lcd{cy} == $$lcd{menu_cnt};
        if ($$lcd{cy} > ($$lcd{dy} + $$lcd{dy_max})) {
            $$lcd{dy} =  $$lcd{cy} - $$lcd{dy_max};
        }
        &menu_lcd_curser_state($lcd, $$lcd{menu_ptr}{items}[$$lcd{cy}]); # Move cursor to the same state
    }
    elsif ($key eq 'left') {
                                # For action state menus, scroll to the previous state
        if ($ptr and $$ptr{Dstates}) {
            $$lcd{menu_state}--;
            &menu_lcd_curser_state($lcd, $ptr);
        }
        else {
            $$lcd{cx} -= 5;
            $$lcd{cx}  = 0 if $$lcd{cx} < 0;
        }
    }
    elsif ($key eq 'right') {
                                # For action state menus, scroll to the next state
        if ($ptr and $$ptr{Dstates}) {
            $$lcd{menu_state}++;
            &menu_lcd_curser_state($lcd, $ptr);
        }
        else {
            my $l = length($$lcd{menu}[$$lcd{cy}]);
            $$lcd{cx} += 5;
            $$lcd{cx} = $l if $$lcd{cx} > $l;
        }
    }
    elsif ($key eq 'enter') {
        $Menus{menu_data}{last_response_object} = $lcd;

                                # Run an action
        if ($ptr and $$ptr{A}) {
            my $response = &menu_run("$$lcd{menu_group},$menu,$$lcd{cy},$$lcd{menu_state},l");
            if ($response) {
                &menu_lcd_display($lcd, $response, $menu);
            }
        }
                                # Display a response
        elsif ($ptr and $$ptr{R}) {
            my $response = &menu_run("$$lcd{menu_group},$menu,$$lcd{cy},$$lcd{menu_state},l");
            if ($response) {
                &menu_lcd_display($lcd, $response, $menu);
            }
        }
                                # Load next menu
        elsif ($ptr) {
            push @{$$lcd{menu_history}}, $menu;
            push @{$$lcd{menu_states}}, join $;, $$lcd{cx}, $$lcd{cy}, $$lcd{dy}, $$lcd{menu_state};
            &menu_lcd_load($lcd, $$ptr{D});
        }
                                # Nothing to do (e.g. response display)
        else {
        }
        return;
    }
    elsif ($key eq 'exit') {
        if (my $menu = pop @{$$lcd{menu_history}}) {
            &menu_lcd_load($lcd, $menu);
            ($$lcd{cx}, $$lcd{cy}, $$lcd{dy}, $$lcd{menu_state}) = 
                split $;, pop @{$$lcd{menu_states}};
        }
    }
    else {
        return;                 # Do not refresh the display if nothing changed
    }
    &menu_lcd_refresh($lcd);  # Refresh the display data data
}

sub menu_lcd_display {
    my ($lcd, $response, $menu) = @_;
    push @{$$lcd{menu_history}}, $menu if $menu;
    push @{$$lcd{menu_states}}, join $;, $$lcd{cx}, $$lcd{cy}, $$lcd{dy}, $$lcd{menu_state};
    $Text::Wrap::columns = 20;
#   @{$$lcd{display}} = split "\n", wrap('', '', $response);
    @{$$lcd{menu}} = split "\n", wrap('', '', $response);
    $$lcd{menu_cnt}  = @{$$lcd{menu}} - 1;
    $$lcd{menu_name} = 'response';
    $$lcd{cx} = $$lcd{cy} = $$lcd{dy} = 0;
    &menu_lcd_refresh($lcd);  # Refresh the display data data
}

sub menu_lcd_curser_state {
    my ($lcd, $ptr) = @_;

                                # State = -1 means cursor at start of line
    if ($$lcd{menu_state} < 0) {
        $$lcd{menu_state} = -1;
        $$lcd{cx}    =  0;
        return;
    }

                                # Limit to maximium state
    if ($$lcd{menu_state} > $#{$$ptr{Dstates}}) {
        $$lcd{menu_state} = $#{$$ptr{Dstates}};
    }

    my $state_name = $$ptr{Dstates}[$$lcd{menu_state}];
    if ($state_name and $$ptr{D} =~ /([\[,]\Q$state_name\E[,\]])/) {
        $$lcd{cx} = 1 + index $$ptr{D}, $1;
    }
}

                                # Format a list of things, based on format
sub menu_format_list {
    my ($format, @list) = @_;

    if ($format eq 'w') {
        return '<select><option>' . join("</option>\n<option>", @list) . '</option></select>'; 
    }
    elsif ($format eq 'h') {
        return join("<br>\n", @list);
    }
    else {
        return join("\n", @list);
    }
}        

                                # Call this to set default menus
sub set_menu_default {
    my ($menu_group, $menu, $address) = @_;
    $Menus{menu_data}{defaults}{$address} = join $;, $menu_group, $menu;
}
sub get_menu_default {
    my ($address) = @_;
    return split $;, $Menus{menu_data}{defaults}{$address};
}

return 1;


#
# $Log$
# Revision 1.9  2002/05/28 13:07:52  winter
# - 2.68 release
#
# Revision 1.8  2001/12/16 21:48:41  winter
# - 2.62 release
#
# Revision 1.7  2001/10/21 01:22:32  winter
# - 2.60 release
#
# Revision 1.6  2001/08/12 04:02:58  winter
# - 2.57 update
#
#