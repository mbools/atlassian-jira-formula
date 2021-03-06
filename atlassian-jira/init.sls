{% from 'atlassian-jira/map.jinja' import jira with context %}

include:
  - java

jira:
  file.managed:
    - name: /etc/systemd/system/atlassian-jira.service
    - source: salt://atlassian-jira/files/atlassian-jira.service
    - template: jinja
    - defaults:
        config: {{ jira }}

  module.wait:
    - name: service.systemctl_reload
    - watch:
      - file: jira

  group.present:
    - name: {{ jira.group }}

  user.present:
    - name: {{ jira.user }}
    - home: {{ jira.dirs.home }}
    - gid: {{ jira.group }}
    - require:
      - group: jira
      - file: jira-dir

  service.running:
    - name: atlassian-jira
    - enable: True
    - require:
      - file: jira

jira-graceful-down:
  service.dead:
    - name: atlassian-jira
    - require:
      - module: jira
    - prereq:
      - file: jira-install

jira-install:
  archive.extracted:
    - name: {{ jira.dirs.extract }}
    - source: {{ jira.url }}
    - source_hash: {{ jira.url_hash }}
    - archive_format: tar
    - tar_options: z
    - if_missing: {{ jira.dirs.current_install }}
    - user: root
    - group: root
    - keep: True
    - require:
      - file: jira-extractdir

  file.symlink:
    - name: {{ jira.dirs.install }}
    - target: {{ jira.dirs.current_install }}
    - require:
      - archive: jira-install
    - watch_in:
      - service: jira

jira-serverxml:
  file.managed:
    - name: {{ jira.dirs.install }}/conf/server.xml
    - source: salt://atlassian-jira/files/server.xml
    - template: jinja
    - defaults:
        config: {{ jira }}
    - require:
      - file: jira-install
    - watch_in:
      - service: jira

jira-dir:
  file.directory:
    - name: {{ jira.dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

jira-home:
  file.directory:
    - name: {{ jira.dirs.home }}
    - user: {{ jira.user }}
    - group: {{ jira.group }}
    - mode: 755
    - require:
      - file: jira-dir
    - makedirs: True

jira-extractdir:
  file.directory:
    - name: {{ jira.dirs.extract }}
    - use:
      - file: jira-dir

jira-scriptdir:
  file.directory:
    - name: {{ jira.dirs.scripts }}
    - use:
      - file: jira-dir

{% for file in [ 'env.sh', 'start.sh', 'stop.sh' ] %}
jira-script-{{ file }}:
  file.managed:
    - name: {{ jira.dirs.scripts }}/{{ file }}
    - source: salt://atlassian-jira/files/{{ file }}
    - user: {{ jira.user }}
    - group: {{ jira.group }}
    - mode: 755
    - template: jinja
    - defaults:
        config: {{ jira }}
    - require:
      - file: jira-scriptdir
      - group: jira
      - user: jira
    - watch_in:
      - service: jira
{% endfor %}

{% if jira.get('crowd') %}
jira-crowd-properties:
  file.managed:
    - name: {{ jira.dirs.install }}/atlassian-jira/WEB-INF/classes/crowd.properties
    - require:
      - file: jira-install
    - watch_in:
      - service: jira
    - contents: |
{%- for key, val in jira.crowd.items() %}
        {{ key }}: {{ val }}
{%- endfor %}
{% endif %}

{% if jira.managedb %}
jira-dbconfig:
  file.managed:
    - name: {{ jira.dirs.home }}/dbconfig.xml
    - source: salt://atlassian-jira/files/dbconfig.xml
    - template: jinja
    - user: {{ jira.user }}
    - group: {{ jira.group }}
    - mode: 640
    - defaults:
        config: {{ jira }}
    - require:
      - file: jira-home
    - watch_in:
      - service: jira
{% endif %}

jira-permission-installdir:
  file.directory:
    - name: {{ jira.dirs.install }}
    - user: {{ jira.user }}
    - group: {{ jira.group }}
    - recurse:
      - user
      - group
    - require:
      - file: jira-install
      - group: jira
      - user: jira
    - require_in:
      - service: jira

jira-disable-JiraSeraphAuthenticator:
  file.blockreplace:
    - name: {{ jira.dirs.install }}/atlassian-jira/WEB-INF/classes/seraph-config.xml
    - marker_start: 'CROWD:START - The authenticator below here will need to be commented'
    - marker_end: 'CROWD:END'
    - content: {% if jira.crowdSSO %}'    <!-- <authenticator class="com.atlassian.jira.security.login.JiraSeraphAuthenticator"/> -->'{% else %}'    <authenticator class="com.atlassian.jira.security.login.JiraSeraphAuthenticator"/>'{% endif %}
    - require:
      - file: jira-install
    - watch_in:
      - service: jira

jira-enable-SSOSeraphAuthenticator:
  file.blockreplace:
    - name: {{ jira.dirs.install }}/atlassian-jira/WEB-INF/classes/seraph-config.xml
    - marker_start: 'CROWD:START - If enabling Crowd SSO integration uncomment'
    - marker_end: 'CROWD:END'
    - content: {% if jira.crowdSSO %}'    <authenticator class="com.atlassian.jira.security.login.SSOSeraphAuthenticator"/>'{% else %}'    <!-- <authenticator class="com.atlassian.jira.security.login.SSOSeraphAuthenticator"/> -->'{% endif %}
    - require:
      - file: jira-install
    - watch_in:
      - service: jira
