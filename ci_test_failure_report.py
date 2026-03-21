import requests
import json
from datetime import date, timedelta
from collections import Counter
from itertools import islice
from threading import Thread

branches = (10.5, 10.6, 10.11, 11.4, 11.6, 11.7)
test_suites = ('rpl.*', 'binlog.*', 'binlog_encryption.*', 'multi_source.*')
report_period = 5 
top_fail_tests_count = 5
frm_dt = str(date.today() - timedelta(report_period))
all_fail_tests_list = list()
final_rpt = dict()

def prepare_branch_rpt(branch):
  '''This function prepares report for the supplied branch.'''
  branch_rpt = dict()
  branch_fail_tests_list = list()

  def prepare_suite_rpt(test_suite):
    '''This function prepares report for the supplied test suite.'''
    print(f"Collecting results for the branch {branch}, test suite {test_suite}, from date {frm_dt}")
    #Construct the CI url to get the JSON data from"
    ci_url = f"https://buildbot.mariadb.net/ci/reports/cross_reference.json? \
              branch={branch}&revision=&platform=& \
              fail_name={test_suite}&fail_variant=&fail_info_full=&typ=&info=& \
              dt={frm_dt}&limit=500&fail_info_short="
    # Making a get request 
    rows = requests.get(ci_url).json() 
    for row in rows: # Collect failing tests specific to the branch
      branch_fail_tests_list.append((row['test_name']))
    
    # Add all tests specific to the branch to the master collection
    all_fail_tests_list.extend(branch_fail_tests_list)

  for test_suite in test_suites:
    prepare_suite_rpt(test_suite)

  # Collect only unique tests specific to the branch
  branch_rpt['unique_fail_tests'] = sorted(list(set(branch_fail_tests_list)))
  final_rpt[branch] = branch_rpt

branch_workers = list()
for branch in branches:
  '''Create threads for each release branch'''
  t = Thread(target=prepare_branch_rpt, args=(branch,))
  branch_workers.append(t)
  t.start()
   
for t in branch_workers:
  t.join()

final_rpt = dict(sorted(final_rpt.items(), key=lambda item: branches.index(item[0])))

# Prepare the final report
tcCounter = Counter(all_fail_tests_list)
tests_with_fail_count = {tc:tcCounter[tc] for tc in all_fail_tests_list}
tests_with_fail_count_reverse = {k: v for k, v in sorted(tests_with_fail_count.items(), key=lambda item: item[1], reverse=True)}
final_rpt['top_fail_tests'] = dict(islice(tests_with_fail_count_reverse.items(), top_fail_tests_count))

print(json.dumps(final_rpt))
