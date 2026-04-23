import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runAssessment from '@salesforce/apex/CreditAssessmentService.runAssessment';

export default class CreditAssessmentButton extends LightningElement {
    @api recordId;

    isLoading = false;
    showError = false;
    showResult = false;
    showInitial = true;
    result = {};
    errorMessage = '';

    handleRunAssessment() {
        this.isLoading = true;
        this.showError = false;
        this.showResult = false;
        this.showInitial = false;

        runAssessment({ accountId: this.recordId })
            .then(result => {
                this.isLoading = false;

                // isError=true means the Apex caught an error and returned an error
                // result instead of throwing (to allow the RFLIB log insert to commit).
                if (result.isError) {
                    this.errorMessage = result.message;
                    this.showError = true;

                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Credit assessment failed. Please contact IT support.',
                            variant: 'error'
                        })
                    );
                    return;
                }

                this.result = result;
                this.showResult = true;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Credit assessment completed',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                console.error('Credit assessment error:', error);
                this.errorMessage = error.body ? error.body.message : error.message;
                this.showError = true;
                this.isLoading = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Credit assessment failed. Please contact IT support.',
                        variant: 'error'
                    })
                );
            });
    }
}
