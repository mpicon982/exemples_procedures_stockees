
create or replace procedure observatoire_mobilites.proc_fd_mobpro_tdb_flux_modes (p_schema_name text default 'public', p_table_name text default 'flux_dt_csp_tdb', p_liste_epci text default NULL)
    LANGUAGE plpgsql AS

$$

DECLARE v_rqt_temp_internes text; --rqt pour table temp contenant les flux internes
        v_rqt_temp_entrants text:=''; --pour flux entrants
        v_rqt_temp_sortants text:=''; -- pour flux sortants
        v_unionall text ; --variable pour gagner du temps dans les boucles avec union all
        v_filtre text[]; --version array de liste_epci
        v_epci text ; --variable n pour les boucles

    --p_liste_epci est utilisé comme filtre, c'est un texte délimité par des ',' que je vasi transformer en array pour filtrer ensuuite

BEGIN
    if p_liste_epci is distinct from '*' then
        if p_liste_epci is NULL then
            raise exception 'Veuillez entrer un ou plusieurs codes EPCI séparés par des virgules' using errcode = 'invalid_parameter_value';

        end if;


        --suppresion espaces en trop
        p_liste_epci := replace(p_liste_epci, ' ', '');
        v_filtre := regexp_split_to_array(p_liste_epci, ',');

        --vérif longueur des codes epci
        if
            (select count(*) nb from unnest(v_filtre) as f(codes) where length(codes) = 9)
                != cardinality(v_filtre)
        then
            raise exception 'Veuillez entrer des codes EPCI de 9 caractères' using errcode = 'invalid_parameter_value';

        end if;

    end if; -- fin du if liste_epci!='*' then
    if p_liste_epci='*' then
    select array_agg(code_epci) from ref_geo.refepci2026 into v_filtre; --récupération de tous les codes EPCI dans le filtre
    end if;
    --maintenant on attaque la création de la table en décomposant en trois tables temp

    --flux internes
    v_rqt_temp_internes:=format($b$ create temporary table temp_internes as(

select 'internes'           type_de_flux,
       o.code_epci          code_epci,
       o.nom_epci           nom_epci,

       case
           when trans = '1' then 'Pas de transport'
           when trans = '2' then 'Marche à pied (ou rollers, patinette)'
           when trans = '3' then 'Vélo (y compris à assistance électrique)'
           when trans = '4' then 'Deux-roues motorisé'
           when trans = '5' then 'Voiture, camion, fourgonnette'
           when trans = '6' then 'Transports en commun'
           when trans = 'Z' then 'Sans objet' end mode_de_transport,

       round(sum(ipondi::numeric)) flux,
       100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over(partition by o.code_epci) part_flux


from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com = m.commune
         join ref_geo.refcom2026 d on d.code_com = m.dclt
where o.code_epci = any(%L)
    and d.code_epci = any(%L) and
            o.code_epci = d.code_epci
group by m.trans, o.code_epci, d.code_epci, o.nom_epci, d.nom_epci);
$b$,v_filtre,v_filtre);

    -- flux entrants
    --l'idée est ici de boucler sur les EPCI du sud 54
    --pour construire les union all de façon récursive plutôt qu'à la main

    FOR v_epci in (select unnest(v_filtre)) loop -- on parcourt la liste d'EPCI (array dim 1 éclaté en table d'une colonne)
    if v_rqt_temp_entrants='' then v_unionall:='';
    else v_unionall:=' union all '; end if;
    v_rqt_temp_entrants:=v_rqt_temp_entrants||v_unionall||format(
            $e$
    select
    'entrants' type_de_flux,
    d.code_epci  code_epci,
    d.nom_epci   nom_epci,
    case
           when trans = '1' then 'Pas de transport'
           when trans = '2' then 'Marche à pied (ou rollers, patinette)'
           when trans = '3' then 'Vélo (y compris à assistance électrique)'
           when trans = '4' then 'Deux-roues motorisé'
           when trans = '5' then 'Voiture, camion, fourgonnette'
           when trans = '6' then 'Transports en commun'
           when trans = 'Z' then 'Sans objet' end mode_de_transport,

    round(sum(coalesce(ipondi::numeric,0))) flux,
    100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over() part_flux

                                             from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com=m.commune
         join ref_geo.refcom2026 d on d.code_com=m.dclt
         where d.code_epci=%L and o.code_epci!=%L
         group by m.trans, d.code_epci,d.nom_epci
                                              $e$, v_epci, v_epci
                                                    );

    --requête flux sortants

    v_rqt_temp_sortants:=v_rqt_temp_sortants||v_unionall||format(
            $d$
    select
    'sortants' type_de_flux,
    o.code_epci  code_epci,
    o.nom_epci   nom_epci,
    case
           when trans = '1' then 'Pas de transport'
           when trans = '2' then 'Marche à pied (ou rollers, patinette)'
           when trans = '3' then 'Vélo (y compris à assistance électrique)'
           when trans = '4' then 'Deux-roues motorisé'
           when trans = '5' then 'Voiture, camion, fourgonnette'
           when trans = '6' then 'Transports en commun'
           when trans = 'Z' then 'Sans objet' end mode_de_transport,

    round(sum(coalesce(ipondi::numeric,0))) flux,
    100.0*sum(coalesce(ipondi::numeric,0))/sum(sum(coalesce(ipondi::numeric,0))) over() part_flux

                                             from rp2023.fd_mobpro_2023 m
         join ref_geo.refcom2026 o on o.code_com=m.commune

         where o.code_epci=%L and m.dclt not in(select code_com from ref_geo.refcom2026 r where r.code_epci=%L)
         group by m.trans, o.code_epci,o.nom_epci
                                              $d$, v_epci,   v_epci
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

    v_rqt_temp_entrants:='create temporary table temp_entrants as('||v_rqt_temp_entrants||');';
    v_rqt_temp_sortants:='create temporary table temp_sortants as('||v_rqt_temp_sortants||');';
    --suppresion préventive des temp tables
    execute 'drop table if exists temp_internes ;';
    execute 'drop table if exists temp_entrants;';
    execute 'drop table if exists temp_sortants';
    --créations des tables temp
    execute v_rqt_temp_internes;
    execute v_rqt_temp_entrants;
    execute v_rqt_temp_sortants;
    --création de la table globale définitive
    execute format('create schema if not exists %I;',p_schema_name);
    execute format('drop table if exists %I.%I',p_schema_name,p_table_name);
    execute format('create table %I.%I as(select * from temp_internes union all select * from temp_entrants union all select * from temp_sortants);',
                   p_schema_name,p_table_name);
    raise notice '☭ table %.% créée camarade ☭',p_schema_name, p_table_name;
    --suppression propre tables temp
    execute 'drop table if exists temp_internes';
    execute 'drop table if exists temp_entrants';
    execute 'drop table if exists temp_sortants';
end;

$$;

/*
1 Pas de transport
2 Marche à pied (ou rollers, patinette)
3 Vélo (y compris à assistance électrique)
4 Deux-roues motorisé
5 Voiture, camion, fourgonnette
6 Transports en commun
Z Sans objet

 */
