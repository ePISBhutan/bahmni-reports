set session group_concat_max_len = 20000;
SET @sql = NULL;
SET @ignoreEmptyValues='#ignoreEmptyValues#';
SET @patientAttributesSql = '#patientAttributes#';
SET @patientAddressesSql = '#patientAddresses#';
SET @visitAttributesSql = '#visitAttributes#';
SET @locationTagsToFilterSql = '#locationTagsToFilter#';
SET @filterByConceptClass = '#conceptClassesToFilter#';
SET @filterByConceptNames = '#conceptNamesToFilter#';
SET @filterByConceptValues = '#conceptValuesToFilter##numericRangesFilterSql#';
SET @filterByEmptyValues='#nullIncludedFilter#';
SET @filterByPrograms = '#programsToFilter#';
SET @dateRangeFilter = '#applyDateRangeFor#';
SET @showProvider = '#showProvider#';
SET @visitTypesToFilterSql = '#visitTypesToFilter#';
SET @extraPatientIdentifierTypes = '#extraPatientIdentifierTypes#';
SET @applyAgeGroup = '#ageGroupName#';
SET @sortByColumns = '#sortByColumns#';
SET @visitAttributeJoinSql = ' LEFT OUTER JOIN visit_attribute va ON va.visit_id=v.visit_id AND va.voided is false
  LEFT OUTER JOIN visit_attribute_type vat ON vat.visit_attribute_type_id = va.attribute_type_id AND vat.retired is false';
SET @patientAttributeJoinSql = ' LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false ';
SET @patientAddressJoinSql = ' LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false ';
SET @conceptClassesToFilterSql = ' JOIN concept_class class ON class.concept_class_id=obs_concept.class_id AND class.name in (#conceptClassesToFilter#)';
SET @conceptNamesToFilterSql = ' AND obs_fscn.name IN (#conceptNamesToFilter#)';
SET @filterByConceptValuesSql = IF(@filterByConceptValues='','', IF(@filterByEmptyValues='',' AND
                                      ((binary o.value_numeric IN (#noValueFilter##conceptValuesToFilter#) OR
                                       o.value_text IN (#noValueFilter##conceptValuesToFilter#) OR
                                       o.value_datetime IN (#noValueFilter##conceptValuesToFilter#) OR
                                       coded_scn.name IN (#noValueFilter##conceptValuesToFilter#) OR
                                       coded_fscn.name IN (#noValueFilter##conceptValuesToFilter#)) #numericRangesFilterSql#)',
                                                                    ' AND
                                                                    ((o.value_numeric IS NULL AND
                                                                     o.value_text IS NULL AND
                                                                     o.value_datetime IS NULL AND
                                                                     coded_scn.name IS NULL AND
                                                                     coded_fscn.name IS NULL) OR
                                       (binary o.value_numeric IN (#noValueFilter##conceptValuesToFilter#) OR
                                       o.value_text IN (#noValueFilter##conceptValuesToFilter#) OR
                                       o.value_datetime IN (#noValueFilter##conceptValuesToFilter#) OR
                                       coded_scn.name IN (#noValueFilter##conceptValuesToFilter#) OR
                                       coded_fscn.name IN (#noValueFilter##conceptValuesToFilter#)) #numericRangesFilterSql#)'));

SET @programsJoinSql = ' JOIN episode_encounter ee ON e.encounter_id = ee.encounter_id
  JOIN episode_patient_program epp ON ee.episode_id=epp.episode_id
  JOIN patient_program pp ON epp.patient_program_id = pp.patient_program_id
  JOIN program program ON pp.program_id = program.program_id';
SET @filterByProgramsSql = '  AND program.name IN (#programsToFilter#)';
SET @dateRangeSql = IF(@dateRangeFilter = 'visitStartDate', ' AND cast(v.date_started AS DATE) BETWEEN "#startDate#" AND "#endDate#"',
                    IF(@dateRangeFilter = 'programDate', ' AND cast(pp.date_enrolled AS DATE) <= "#endDate#"  AND (cast(pp.date_completed AS DATE) >= "#startDate#" or  pp.date_completed is NULL)',
                    IF(@dateRangeFilter = 'visitStopDate', ' AND cast(v.date_stopped AS DATE) BETWEEN "#startDate#" AND "#endDate#"',
                    IF(@dateRangeFilter = 'obsCreatedDate', ' AND cast(o.date_created AS DATE) BETWEEN "#startDate#" AND "#endDate#"', ' AND cast(o.obs_datetime AS DATE) BETWEEN "#startDate#" AND "#endDate#"'))));
SET @providerJoinSql = '  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id';
SET @providerSelectSql = 'coalesce(pro.name, concat(provider_person.given_name, " ", provider_person.family_name)) AS "Provider"';
SET @ageGroupJoinSql = 'LEFT JOIN reporting_age_group rag ON DATE(o.obs_datetime) BETWEEN (DATE_ADD(
                     DATE_ADD(p.birthdate, INTERVAL rag.min_years YEAR), INTERVAL rag.min_days DAY)) AND (DATE_ADD(
                     DATE_ADD(p.birthdate, INTERVAL rag.max_years YEAR), INTERVAL rag.max_days DAY))
                                                       AND rag.report_group_name = "#ageGroupName#"';
SET @ageGroupSelectSql = 'rag.name AS "#ageGroupName#", rag.sort_order AS "Age Group Order"';

SET @primaryIdentifierTypeUuid = NULL;
SELECT property_value FROM global_property WHERE property = 'bahmni.primaryIdentifierType' into @primaryIdentifierTypeUuid;
SET @primaryIdentifierTypeName = NULL;
SELECT name FROM patient_identifier_type WHERE uuid = @primaryIdentifierTypeUuid INTO @primaryIdentifierTypeName;
SET @sql = CONCAT('SELECT
  GROUP_CONCAT(DISTINCT(IF(pit.name = @primaryIdentifierTypeName, pi.identifier, NULL)))     AS "Patient Identifier",
  ',IF(@extraPatientIdentifierTypes = '', '', CONCAT(@extraPatientIdentifierTypes, ',')),'
  concat(pn.given_name, " ", pn.family_name)                    AS "Patient Name",
  floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS "Age",
  DATE_FORMAT(p.birthdate, "%d-%b-%Y")                          AS "Birthdate",
  p.gender                                                      AS "Gender",
  ',IF(@patientAttributesSql = '', '', CONCAT(@patientAttributesSql, ',')),'
  ',IF(@patientAddressesSql = '', '', CONCAT(@patientAddressesSql, '')),'
  ',IF(@visitAttributesSql = '', '', CONCAT(@visitAttributesSql, ',')),'
  ',IF(@applyAgeGroup = '', '', CONCAT(@ageGroupSelectSql, ',')),'
  l.name                                                        AS "Location name",
  #concept_name_sql#                         AS "Concept Name",
  coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name) AS "Value",
  o.obs_datetime                                                AS "Observation Datetime",
  DATE_FORMAT(o.obs_datetime, "%d-%b-%Y")                       AS "Observation Date",
  DATE_FORMAT(o.date_created, "%d-%b-%Y")                       AS "Observation Created Date",
  parent_cn.name                                                AS "Parent Concept",
  ',IF(@showProvider = '', '', CONCAT(@providerSelectSql, ',')),'
  DATE_FORMAT(v.date_started, "%d-%b-%Y")                       AS "Visit Start Date",
  DATE_FORMAT(v.date_stopped, "%d-%b-%Y")                       AS "Visit Stop Date",
  vt.name                                                       AS "Visit Type",
  o.obs_id                                                      AS "Obs Id",
  o.obs_group_id                                                AS "Obs Group Id",
  o.concept_id                                                  AS "Concept Id",
  o.person_id                                                   AS "Patient Id",
  o.encounter_id                                                AS "Encounter Id",
  o.order_id                                                    AS "Order Id",
  v.visit_id                                                    AS "Visit Id",
  program.name                                                  AS "Program Name",
  DATE_FORMAT(pp.date_enrolled, "%d-%b-%Y")                     AS "Program Enrollment Date",
  DATE_FORMAT(pp.date_completed, "%d-%b-%Y")                    AS "Program End Date",
  DATE_FORMAT(p.date_created, "%d-%b-%Y")                       AS "Patient Created Date"

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  ',IF(@filterByConceptNames = '', '', @conceptNamesToFilterSql) ,'
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  ',IF(@filterByConceptClass = '', '', @conceptClassesToFilterSql),'
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false
  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  ',IF(@showProvider = '', '', @providerJoinSql),'
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  ',IF(@applyAgeGroup = '', '', @ageGroupJoinSql),'
  LEFT OUTER JOIN location l ON e.location_id = l.location_id AND l.retired is false
  LEFT OUTER JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT OUTER JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_fscn.concept_name_type="SHORT" AND coded_scn.voided is false
  ',IF(@visitAttributesSql = '', '', @visitAttributeJoinSql),'
  ',IF(@patientAttributesSql = '', '', @patientAttributeJoinSql),'
  ',IF(@patientAddressesSql = '', '', @patientAddressJoinSql),'
  ',IF(@filterByPrograms != '' OR @dateRangeFilter = 'programDate', @programsJoinSql, 'LEFT JOIN episode_encounter ee ON e.encounter_id = ee.encounter_id
  LEFT JOIN episode_patient_program epp ON ee.episode_id=epp.episode_id
  LEFT JOIN patient_program pp ON epp.patient_program_id = pp.patient_program_id
  LEFT JOIN program program ON pp.program_id = program.program_id'),'
  ',IF(@filterByPrograms != '', @filterByProgramsSql, ''),'
WHERE o.voided is false
  ',IF(@locationTagsToFilterSql = '', '', 'AND l.location_id in (SELECT ltm.location_id from location_tag_map ltm JOIN location_tag lt
  ON ltm.location_tag_id=lt.location_tag_id AND lt.retired is false AND lt.name in (#locationTagsToFilter#))'),'
  ',@dateRangeSql,IF(@visitTypesToFilterSql = '', '', 'AND vt.name in (#visitTypesToFilter#)'),
  IF(@filterByConceptValues = '', '', @filterByConceptValuesSql),
                  ' GROUP BY o.obs_id ',IF(@ignoreEmptyValues = '', '', @ignoreEmptyValues),'
                  ', IF(@sortByColumns != '', @sortByColumns, ''), ';');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;





