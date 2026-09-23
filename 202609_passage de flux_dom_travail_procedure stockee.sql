
create or replace procedure observatoire_mobilites.proc_fd_mobpro_tdb_flux_csp (schema_name text default 'public', table_name text default 'flux_dt_csp_tdb', liste_epci text default NULL)
    LANGUAGE plpgsql AS

    $$

        DECLARE rqt_temp_internes text; --rqt pour table temp contenant les flux internes
        rqt_temp_entrants text:=''; --pour flux entrants
        rqt_temp_sortants text:=''; -- pour flux sortants
        unionall text ; --variable pour gagner du temps dans les boucles avec union all
        filtre text[]; --version array de liste_epci
        epci text ; --variable n pour les boucles
        tous_epci text:=''; --variable pour supprimer le filtre where en case de sélection de '*' EPCI en entrée
        --liste_epci est utilisé comme filtre, c'est un texte délimité par des ',' que je vasi transformer en array pour filtrer ensuuite

        BEGIN
        if liste_epci is distinct from '*' then
            if liste_epci is NULL then
                raise warning 'Veuillez entrer un ou plusieurs codes EPCI séparés par des virgules';
                return;
            end if;

            if liste_epci is not NULL
                then
                    --suppresion espaces en trop
                    liste_epci:=replace(liste_epci,' ','');
                    filtre:=regexp_split_to_array(liste_epci,',');

                    --vérif longueur des codes epci
                       if
                          (
                           select count(*) nb from unnest(filtre) as f(codes) where length(codes)=9)
                                                                                        !=cardinality(filtre)
                            then raise warning 'Veuillez entrer des codes EPCI de 9 caractères';
                                return;
                    end if;
            end if;
        end if; -- fin du if liste_epci!='*' then
        if liste_epci='*' then tous_epci='--'; -- implémentation de la variable qui supprimme le filtre passant la ligne where en com
        select array_agg(code_epci) from ref_geo.refepci2026 into filtre; --récupération de tous les codes EPCI dans le filtre
        end if;
        --maintenant on attaque la création de la table en décomposant en trois tables temp

        --flux internes
            rqt_temp_internes:=format($b$ create temporary table temp_internes as(

select 'internes'           type_de_flux,
       o.code_epci          code_epci,
       o.nom_epci           nom_epci,

       case
           when gs = '1'
               then 'Agriculteurs exploitants / Agricultrices exploitantes'
           when gs = '2' then $d$Artisans / Artisanes, commerçants / commerçantes et chefs / cheffes d'entreprise$d$
           when gs = '3' then 'Cadres et professions intellectuelles supérieures'
           when gs = '4' then 'Professions intermédiaires'
           when gs = '5' then 'Employés / Employées'
           when gs = '6' then 'Ouvriers / Ouvrières'
           when gs = 'Z' then 'Sans objet'
           end              groupe_socioprofessionnel_en_6_postes,
       round(sum(ipondi::numeric)) flux,
       100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over(partition by o.code_epci) part_flux


from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com = m.commune
         join ref_geo.refcom2026 d on d.code_com = m.dclt
where %s o.code_epci = any(%L)
  %s and d.code_epci = any(%L) and
            o.code_epci = d.code_epci
group by gs, o.code_epci, d.code_epci, o.nom_epci, d.nom_epci);
$b$,tous_epci,filtre,tous_epci,filtre);

            -- flux entrants
            --l'idée est ici de boucler sur les EPCI du sud 54
            --pour construire les union all de façon récursive plutôt qu'à la main

            FOR epci in (select unnest(filtre)) loop -- on parcourt la liste d'EPCI (array dim 1 éclaté en table d'une colonne)
                    if rqt_temp_entrants='' then unionall:='';
                    else unionall:=' union all '; end if;
                    rqt_temp_entrants:=rqt_temp_entrants||unionall||format(
                            $e$
    select
    'entrants' type_de_flux,
    d.code_epci  code_epci,
    d.nom_epci   nom_epci,
    case
        when gs = '1'
            then 'Agriculteurs exploitants / Agricultrices exploitantes'
        when gs = '2' then $c$Artisans / Artisanes, commerçants / commerçantes et chefs / cheffes d'entreprise$c$
        when gs = '3' then 'Cadres et professions intellectuelles supérieures'
        when gs = '4' then 'Professions intermédiaires'
        when gs = '5' then 'Employés / Employées'
        when gs = '6' then 'Ouvriers / Ouvrières'
        when gs = 'Z' then 'Sans objet'
        end              groupe_socioprofessionnel_en_6_postes,
    round(sum(coalesce(ipondi::numeric,0))) flux,
    100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over() part_flux

                                             from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com=m.commune
         join ref_geo.refcom2026 d on d.code_com=m.dclt
         where d.code_epci=%L and o.code_epci!=%L
         group by m.gs, d.code_epci,d.nom_epci
                                              $e$, epci, epci
                                                                );

            --requête flux sortants

            rqt_temp_sortants:=rqt_temp_sortants||unionall||format(
                    $d$
    select
    'sortants' type_de_flux,
    o.code_epci  code_epci,
    o.nom_epci   nom_epci,
    case
        when gs = '1'
            then 'Agriculteurs exploitants / Agricultrices exploitantes'
        when gs = '2' then 'Artisans / Artisanes, commerçants / commerçantes et chefs / cheffes d''entreprise'
        when gs = '3' then 'Cadres et professions intellectuelles supérieures'
        when gs = '4' then 'Professions intermédiaires'
        when gs = '5' then 'Employés / Employées'
        when gs = '6' then 'Ouvriers / Ouvrières'
        when gs = 'Z' then 'Sans objet'
        end              groupe_socioprofessionnel_en_6_postes,
    round(sum(coalesce(ipondi::numeric,0))) flux,
    100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over() part_flux

                                             from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com=m.commune

         where o.code_epci=%L and m.dclt not in(select code_com from ref_geo.refcom2026 r where r.code_epci=%L)
         group by m.gs, o.code_epci,o.nom_epci
                                              $d$, epci,   epci
                                                                );
            end loop;

--finalisation de la procédure --> construction finale des rqt entr sort, hors boucle, exécution des rqt et nettoyage des rqt temp.
            --raise notice de contrôle de la requête internes
            --raise notice '%',rqt_temp_internes;
            --raise notice de contrôle de la requête entrants
            -- raise notice '%', rqt_temp_entrants;
            --cntrôle de la requête des flux sortants
            --raise notice '%', rqt_temp_sortants;

            --ajout des create dans les requêtes

            rqt_temp_entrants:='create temporary table temp_entrants as('||rqt_temp_entrants||');';
            rqt_temp_sortants:='create temporary table temp_sortants as('||rqt_temp_sortants||');';
            --suppresion préventive des temp tables
            execute 'drop table if exists temp_internes ;';
            execute 'drop table if exists temp_entrants;';
            execute 'drop table if exists temp_sortants';
            --créations des tables temp
            execute rqt_temp_internes;
            execute rqt_temp_entrants;
            execute rqt_temp_sortants;
            --création de la table globale définitive
            execute format('create schema if not exists %I;',schema_name);
            execute format('drop table if exists %I.%I',schema_name,table_name);
            execute format('create table %I.%I as(select * from temp_internes union all select * from temp_entrants union all select * from temp_sortants);',
                            schema_name,table_name);
            raise notice '☭ table %.% créée camarade ☭',schema_name, table_name;
            --suppression propre tables temp
            execute 'drop table if exists temp_internes';
            execute 'drop table if exists temp_entrants';
            execute 'drop table if exists temp_sortants';
        end;

    $$;

--test
call observatoire_mobilites.proc_fd_mobpro_tdb_flux_csp('__atlas_2026_projets','flux_tdb_csp_sddv','200071066');


select * from __atlas_2026_projets.flux_tdb_csp_sddv