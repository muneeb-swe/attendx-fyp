from django.contrib import admin
from django.db.models import Count, Q
from django.template.response import TemplateResponse
from django.urls import path
from django.utils.html import format_html

from .models import Class, Enrollment, Session, AttendanceRecord


@admin.register(AttendanceRecord)
class AttendanceRecordAdmin(admin.ModelAdmin):
    """
    Per-record transparency: every mark, whether it was signature-
    verified, whether a teacher modified it, and what it originally
    said. This is the row-level view; see the aggregate 'Attendance
    Stats' page (linked at the top of this list) for totals.
    """

    list_display = [
        'session', 'student_roll', 'status', 'original_status_display',
        'modified_badge', 'signature_badge', 'timestamp',
    ]
    list_filter = ['status', 'is_modified', 'session__class_obj']
    search_fields = ['student__roll_number', 'session__id']
    ordering = ['-timestamp']
    readonly_fields = ['signature', 'timestamp']

    change_list_template = 'admin/attendance/attendancerecord/change_list.html'

    def has_delete_permission(self, request, obj=None):
        # This IS the attendance history the stats page reports on —
        # deleting rows here would silently corrupt the transparency
        # numbers this dashboard exists to show.
        return False

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path('stats/', self.admin_site.admin_view(self.stats_view), name='attendance-stats'),
        ]
        return custom + urls

    def stats_view(self, request):
        qs = AttendanceRecord.objects.all()

        total = qs.count()
        present = qs.filter(status='present').count()
        absent = qs.filter(status='absent').count()
        manual = qs.filter(status='manual').count()

        modified = qs.filter(is_modified=True).count()
        absent_to_present = qs.filter(
            is_modified=True, original_status='absent', status='present'
        ).count()
        present_to_absent = qs.filter(
            is_modified=True, original_status='present', status='absent'
        ).count()

        signed = qs.exclude(signature='').count()
        unsigned = qs.filter(signature='').count()

        context = dict(
            self.admin_site.each_context(request),
            title='Attendance Stats',
            total=total,
            present=present,
            absent=absent,
            manual=manual,
            modified=modified,
            modified_pct=round(modified / total * 100, 1) if total else 0,
            absent_to_present=absent_to_present,
            present_to_absent=present_to_absent,
            signed=signed,
            unsigned=unsigned,
        )
        return TemplateResponse(request, 'admin/attendance/stats.html', context)

    @admin.display(description='Student', ordering='student__roll_number')
    def student_roll(self, obj):
        return obj.student.roll_number

    @admin.display(description='Original Status', ordering='original_status')
    def original_status_display(self, obj):
        return obj.original_status

    @admin.display(description='Modified?', ordering='is_modified')
    def modified_badge(self, obj):
        if obj.is_modified:
            return format_html('<span style="color:#b8860b;font-weight:600;">Modified</span>')
        return '—'

    @admin.display(description='Signature')
    def signature_badge(self, obj):
        if obj.signature:
            return format_html('<span style="color:#1a7f37;">Verified</span>')
        return format_html('<span style="color:#999;">None (manual override)</span>')


@admin.register(Class)
class ClassAdmin(admin.ModelAdmin):
    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Enrollment)
class EnrollmentAdmin(admin.ModelAdmin):
    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Session)
class SessionAdmin(admin.ModelAdmin):
    """
    Deleting a Session cascades to its AttendanceRecords too (same
    CASCADE risk as Device). Sessions already have proper app-level
    lifecycle methods (stop/submit/discard) — deleting the row
    directly from admin bypasses all of that, so it's disabled here.
    """
    def has_delete_permission(self, request, obj=None):
        return False
