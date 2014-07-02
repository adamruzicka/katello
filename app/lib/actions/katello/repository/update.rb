#
# Copyright 2014 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

module Actions
  module Katello
    module Repository
      class Update < Actions::EntryAction

        def plan(repository, repo_params)
          repository.disable_auto_reindex!
          action_subject repository
          repository.update_attributes!(repo_params)
          plan_action(::Actions::Candlepin::Content::Update, 
                      :content_id => repository.content_id,
                      :name => repository.name,
                      :content_url => ::Katello::Glue::Pulp::Repos.custom_content_path(repository.product, repository.label),
                      :gpg_url => repository.yum_gpg_key_url,
                      :label => repository.custom_content_label,
                      :type => repository.content_type,
                      :vendor => ::Katello::Provider::CUSTOM)

          if (repository.previous_changes.key?('feed') || repository.previous_changes.key?('unprotected')) &&
              !repository.product.provider.redhat_provider?
            plan_action(::Actions::Pulp::Repository::Refresh, repository)
          end
          
          if repository.previous_changes.key?('unprotected')
            plan_action(::Actions::Katello::Repository::NodeMetadataGenerate, repository)
          end

          plan_action ElasticSearch::Reindex, repository
        end
      end
    end
  end
end
