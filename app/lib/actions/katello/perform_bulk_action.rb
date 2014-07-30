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
    class PerformBulkAction < Actions::EntryAction

      middleware.use Actions::Middleware::KeepCurrentUser
      
      SubPlanFinished = Algebrick.type do
        fields! :execution_plan_id => String
      end
      
      # == Parameters:
      # actions_class::
      #   Class of action to trigger on targets
      # targets::
      #   Array of objects on which the action_class should be triggered
      # *args::
      #   Arguments that all the targets share
      def plan(action_class, targets, *args)
        check_target_classes!(targets)
        plan_self(:action_class => action_class.to_s,
                  :target_ids => targets.map(&:id),
                  :target_class => targets.first.class.to_s,
                  :args => args)
      end
      
      def humanized_name
        _("Bulk action: %s") % input[:action_class]
      end
      
      def run(event = nil)
        case(event)
        when nil
          initiate_sub_plans
        when SubPlanFinished
          mark_as_done(event.execution_plan_id)
          if done?
            check_for_errors!
          else
            suspend
          end
        end
      end

      def initiate_sub_plans
        action_class = input[:action_class].constantize
        planned_sub_plans = []
        target_class = input[:target_class].constantize
        targets = target_class.where(:id => input[:target_ids])
        output[:finished_sub_plan_ids] = []
        output[:failed_sub_plan_ids] = []
        output[:sub_plan_ids] = targets.map do |target|
          ForemanTasks.trigger(action_class, target, *input[:args]).tap do |sub_plan|
            if sub_plan.planned?
              planned_sub_plans << sub_plan
            else
              output[:failed_sub_plan_ids] << sub_plan.execution_plan_id
            end
            sub_plan.execution_plan_id
          end
        end
        if planned_sub_plans.any?
          suspend do |suspended_action|
            planned_sub_plans.each do |sub_plan|
              sub_plan.finished.do_then do
                suspended_action << SubPlanFinished[sub_plan.execution_plan_id]
              end
            end
          end
        else
          check_for_errors!
        end
      end
      
      def mark_as_done(plan_id)
        output[:finished_sub_plan_ids] << plan_id
      end

      def done?
        left = output[:sub_plan_ids].size
        left -= output[:finished_sub_plan_ids].size
        left -= output[:failed_sub_plan_ids].size
        left <= 0
      end

      def check_target_classes!(targets)
        if targets.map(&:class).uniq.length > 1
          fail "The targets are of different types"
        end
      end

      def check_for_errors!
        fail "There was some task failing" if output[:failed_sub_plan_ids].size > 0
      end
    end
  end
end

